local is_contact_subscribed = require"core.rostermanager".is_contact_subscribed;
local jid_split = require"util.jid".split;
local jid_bare = require"util.jid".bare;
local st = require"util.stanza";
local datetime = require"util.datetime";

local presence_cache = {}; -- Reload to empty

local function cache_hook(event)
	local origin, stanza = event.origin, event.stanza;
	local typ = stanza.attr.type;
	module:log("debug", "Cache hook, got %s from a %s", stanza:top_tag(), origin.type);
	if origin.type == "s2sin" and ( typ == nil or typ == "unavailable" ) then
		local from_jid = stanza.attr.from;
		local from_bare = jid_bare(from_jid);
		local username = jid_split(stanza.attr.to);

		if not is_contact_subscribed(username, module.host, from_bare) then
			module:log("debug", "Not in their roster", origin.username);
			return;
		end

		local user_presence_cache = presence_cache[username];
		if not user_presence_cache then
			user_presence_cache = {};
			presence_cache[username] = user_presence_cache;
		end

		local contact_presence_cache = user_presence_cache[from_bare];
		if not contact_presence_cache then
			contact_presence_cache = {};
			user_presence_cache[from_bare] = contact_presence_cache;
		end

		if typ == "unavailable" then
			contact_presence_cache[from_jid] = nil;
			if next(contact_presence_cache) == nil or from_jid == from_bare then
				user_presence_cache[from_bare] = nil;
				if next(user_presence_cache) == nil then
					presence_cache[username] = nil;
				end
			end
		else -- only cache binary state
			contact_presence_cache[from_jid] = datetime.datetime();
		end
	end
end

module:hook("presence/bare", cache_hook, 10);
-- module:hook("presence/full", cache_hook, 10);

local function answer_probe_from_cache(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type ~= "probe" then return; end
	local contact_bare = stanza.attr.to;

	local user_presence_cache = presence_cache[origin.username];
	if not user_presence_cache then return; end

	local contact_presence_cache = user_presence_cache[contact_bare];
	if not contact_presence_cache then return; end

	local user_jid = stanza.attr.from;
	for jid, presence in pairs(contact_presence_cache) do
		module:log("debug", "Sending cached presence from %s", jid);
		if presence == true then
			presence = st.presence({ from = user_jid, from = jid });
		elseif type(presence) == "string" then -- a timestamp
			presence = st.presence({ from = user_jid, from = jid })
				:tag("delay", { xmlns = "urn:xmpp:delay", from = module.host, stamp = presence }):up();
		end
		origin.send(presence);
	end
end

module:hook("pre-presence/bare", answer_probe_from_cache, 10);

module:add_timer(3600, function (now)
	local older = datetime.datetime(now - 7200);
	for username, user_presence_cache in pairs(presence_cache) do
		for contact, contact_presence_cache in pairs(user_presence_cache) do
			for jid, presence in pairs(contact_presence_cache) do
				if presence == true or (type(presence) == "string" and presence < older) then
					contact_presence_cache[jid] = nil;
				end
			end
			if next(contact_presence_cache) == nil then
				user_presence_cache[contact] = nil;
			end
		end
		if next(user_presence_cache) == nil then
			presence_cache[username] = nil;
		end
	end
	return 3600;
end);

