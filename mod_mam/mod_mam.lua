-- XEP-0313: Message Archive Management for Prosody
-- Copyright (C) 2011-2016 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local xmlns_mam     = "urn:xmpp:mam:0";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";

local um = require "core.usermanager";
local st = require "util.stanza";
local rsm = module:require "rsm";
local get_prefs = module:require"mamprefs".get;
local set_prefs = module:require"mamprefs".set;
local prefs_to_stanza = module:require"mamprefsxml".tostanza;
local prefs_from_stanza = module:require"mamprefsxml".fromstanza;
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local dataform = require "util.dataforms".new;
local host = module.host;

local rm_load_roster = require "core.rostermanager".load_roster;

local getmetatable = getmetatable;
local function is_stanza(x)
	return getmetatable(x) == st.stanza_mt;
end

local tostring = tostring;
local time_now = os.time;
local m_min = math.min;
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local default_max_items, max_max_items = 20, module:get_option_number("max_archive_query_results", 50);
local global_default_policy = module:get_option("default_archive_policy", true);
if global_default_policy ~= "roster" then
	global_default_policy = module:get_option_boolean("default_archive_policy", global_default_policy);
end

local archive_store = "archive2";
local archive = assert(module:open_store(archive_store, "archive"));

if archive.name == "null" or not archive.find then
	if not archive.find then
		module:log("debug", "Attempt to open archive storage returned a valid driver but it does not seem to implement the storage API");
		module:log("debug", "mod_%s does not support archiving", archive._provided_by or archive.name and "storage_"..archive.name.."(?)" or "<unknown>");
	else
		module:log("debug", "Attempt to open archive storage returned null driver");
	end
	module:log("debug", "See https://prosody.im/doc/storage and https://prosody.im/doc/archiving for more information");
	module:log("info", "Using in-memory fallback archive driver");
	archive = module:require "fallback_archive";
end

local cleanup;

-- Handle prefs.
module:hook("iq/self/"..xmlns_mam..":prefs", function(event)
	local origin, stanza = event.origin, event.stanza;
	local user = origin.username;
	if stanza.attr.type == "get" then
		local prefs = prefs_to_stanza(get_prefs(user));
		local reply = st.reply(stanza):add_child(prefs);
		origin.send(reply);
	else -- type == "set"
		local new_prefs = stanza:get_child("prefs", xmlns_mam);
		local prefs = prefs_from_stanza(new_prefs);
		local ok, err = set_prefs(user, prefs);
		if not ok then
			origin.send(st.error_reply(stanza, "cancel", "internal-server-error", "Error storing preferences: "..tostring(err)));
		else
			origin.send(st.reply(stanza));
		end
	end
	return true;
end);

local query_form = dataform {
	{ name = "FORM_TYPE"; type = "hidden"; value = xmlns_mam; };
	{ name = "with"; type = "jid-single"; };
	{ name = "start"; type = "text-single" };
	{ name = "end"; type = "text-single"; };
};

-- Serve form
module:hook("iq-get/self/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	origin.send(st.reply(stanza):add_child(query_form:form()));
	return true;
end);

-- Handle archive queries
module:hook("iq-set/self/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local query = stanza.tags[1];
	local qid = query.attr.queryid;

	if cleanup then cleanup[origin.username] = true; end

	-- Search query parameters
	local qwith, qstart, qend;
	local form = query:get_child("x", "jabber:x:data");
	if form then
		local err;
		form, err = query_form:data(form);
		if err then
			origin.send(st.error_reply(stanza, "modify", "bad-request", select(2, next(err))));
			return true;
		end
		qwith, qstart, qend = form["with"], form["start"], form["end"];
		qwith = qwith and jid_bare(qwith); -- dataforms does jidprep
	end

	if qstart or qend then -- Validate timestamps
		local vstart, vend = (qstart and timestamp_parse(qstart)), (qend and timestamp_parse(qend));
		if (qstart and not vstart) or (qend and not vend) then
			origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid timestamp"))
			return true;
		end
		qstart, qend = vstart, vend;
	end

	module:log("debug", "Archive query, id %s with %s from %s until %s)",
		tostring(qid), qwith or "anyone", qstart or "the dawn of time", qend or "now");

	-- RSM stuff
	local qset = rsm.get(query);
	local qmax = m_min(qset and qset.max or default_max_items, max_max_items);
	local reverse = qset and qset.before or false;
	local before, after = qset and qset.before, qset and qset.after;
	if type(before) ~= "string" then before = nil; end


	-- Load all the data!
	local data, err = archive:find(origin.username, {
		start = qstart; ["end"] = qend; -- Time range
		with = qwith;
		limit = qmax + 1;
		before = before; after = after;
		reverse = reverse;
		total = true;
	});

	if not data then
		origin.send(st.error_reply(stanza, "cancel", "internal-server-error", err));
		return true;
	end
	local total = tonumber(err);

	origin.send(st.reply(stanza));
	local msg_reply_attr = { to = stanza.attr.from, from = stanza.attr.to };

	local results = {};

	-- Wrap it in stuff and deliver
	local first, last;
	local count = 0;
	local complete = "true";
	for id, item, when in data do
		count = count + 1;
		if count > qmax then
			complete = nil;
			break;
		end
		local fwd_st = st.message(msg_reply_attr)
			:tag("result", { xmlns = xmlns_mam, queryid = qid, id = id })
				:tag("forwarded", { xmlns = xmlns_forward })
					:tag("delay", { xmlns = xmlns_delay, stamp = timestamp(when) }):up();

		if not is_stanza(item) then
			item = st.deserialize(item);
		end
		item.attr.xmlns = "jabber:client";
		fwd_st:add_child(item);

		if not first then first = id; end
		last = id;

		if reverse then
			results[count] = fwd_st;
		else
			origin.send(fwd_st);
		end
	end

	if reverse then
		for i = #results, 1, -1 do
			origin.send(results[i]);
		end
		first, last = last, first;
	end

	-- That's all folks!
	module:log("debug", "Archive query %s completed", tostring(qid));

	origin.send(st.message(msg_reply_attr)
		:tag("fin", { xmlns = xmlns_mam, queryid = qid, complete = complete })
			:add_child(rsm.generate {
				first = first, last = last, count = total }));
	return true;
end);

local function has_in_roster(user, who)
	local roster = rm_load_roster(user, host);
	module:log("debug", "%s has %s in roster? %s", user, who, roster[who] and "yes" or "no");
	return roster[who];
end

local function shall_store(user, who)
	-- TODO Cache this?
	if not um.user_exists(user, host) then
		return false;
	end
	local prefs = get_prefs(user);
	local rule = prefs[who];
	module:log("debug", "%s's rule for %s is %s", user, who, tostring(rule));
	if rule ~= nil then
		return rule;
	end
	-- Below could be done by a metatable
	local default = prefs[false];
	module:log("debug", "%s's default rule is %s", user, tostring(default));
	if default == nil then
		default = global_default_policy;
		module:log("debug", "Using global default rule, %s", tostring(default));
	end
	if default == "roster" then
		return has_in_roster(user, who);
	end
	return default;
end

-- Handle messages
local function message_handler(event, c2s)
	local origin, stanza = event.origin, event.stanza;
	local log = c2s and origin.log or module._log;
	local orig_type = stanza.attr.type or "normal";
	local orig_from = stanza.attr.from;
	local orig_to = stanza.attr.to or orig_from;
	-- Stanza without 'to' are treated as if it was to their own bare jid

	-- We store chat messages or normal messages that have a body
	if not(orig_type == "chat" or (orig_type == "normal" and stanza:get_child("body")) ) then
		log("debug", "Not archiving stanza: %s (type)", stanza:top_tag());
		return;
	end
	-- or if hints suggest we shouldn't
	if stanza:get_child("no-permanent-storage", "urn:xmpp:hints") -- The XEP needs to decide on "store" or "storage"
	or stanza:get_child("no-permanent-store", "urn:xmpp:hints")
	or stanza:get_child("no-storage", "urn:xmpp:hints")
	or stanza:get_child("no-store", "urn:xmpp:hints") then
		log("debug", "Not archiving stanza: %s (hint)", stanza:top_tag());
		return;
	end

	-- Whos storage do we put it in?
	local store_user = c2s and origin.username or jid_split(orig_to);
	-- And who are they chatting with?
	local with = jid_bare(c2s and orig_to or orig_from);

	-- Check with the users preferences
	if shall_store(store_user, with) then
		log("debug", "Archiving stanza: %s", stanza:top_tag());

		-- And stash it
		local ok, id = archive:append(store_user, nil, stanza, time_now(), with);
		if ok then
			if cleanup then cleanup[store_user] = true; end
			module:fire_event("archive-message-added", { origin = origin, stanza = stanza, for_user = store_user, id = id });
		end
	else
		log("debug", "Not archiving stanza: %s (prefs)", stanza:top_tag());
	end
end

local function c2s_message_handler(event)
	return message_handler(event, true);
end

local cleanup_after = module:get_option_string("archive_expires_after", "1w");
local cleanup_interval = module:get_option_number("archive_cleanup_interval", 4 * 60 * 60);
if cleanup_after ~= "never" then
	local day = 86400;
	local multipliers = { d = day, w = day * 7, m = 31 * day, y = 365.2425 * day };
	local n, m = cleanup_after:lower():match("(%d+)%s*([dwmy]?)");
	if not n then
		module:log("error", "Could not parse archive_expires_after string %q", cleanup_after);
		return false;
	end

	cleanup_after = tonumber(n) * ( multipliers[m] or 1 );

	module:log("debug", "archive_expires_after = %d -- in seconds", cleanup_after);

	if not archive.delete then
		module:log("error", "archive_expires_after set but mod_%s does not support deleting", archive._provided_by);
		return false;
	end

	cleanup = {};

	pcall(function ()
		for user in um.users(module.host) do
			cleanup[user] = true;
		end
	end);

	module:add_timer(math.random(10, 60), function()
		local user = next(cleanup);
		if user then
			module:log("debug", "Removing old messages for user %q", user);
			local ok, err = archive:delete(user, { ["end"] = os.time() - cleanup_after; })
			if not ok then
				module:log("warn", "Could not expire archives for user %s: %s", user, err);
			else
				-- :affected() is a recent addition for eg SQLite3 in LuaDBI
				pcall(function(stmt)
					module:log("debug", "Removed %d messages", stmt:affected());
				end, err);
			end
			cleanup[user] = nil;
		end
		return math.random(cleanup_interval, cleanup_interval * 2);
	end);
end

-- Stanzas sent by local clients
module:hook("pre-message/bare", c2s_message_handler, 2);
module:hook("pre-message/full", c2s_message_handler, 2);
-- Stanszas to local clients
module:hook("message/bare", message_handler, 2);
module:hook("message/full", message_handler, 2);

module:add_feature(xmlns_mam); -- COMPAT with XEP-0313 v 0.1

module:hook("account-disco-info", function(event)
	(event.reply or event.stanza):tag("feature", {var=xmlns_mam}):up();
end);

