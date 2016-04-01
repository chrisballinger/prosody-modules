local is_contact_subscribed = require"core.rostermanager".is_contact_subscribed;
local jid_split = require"util.jid".split;
local jid_bare = require"util.jid".bare;
local st = require"util.stanza";
local datetime = require"util.datetime";
local cache = require "util.cache";

local cache_size = module:get_option_number("presence_cache_size", 100);

local bare_cache = {}; -- [username NUL bare_jid] = { [full_jid] = timestamp, ... }

local function on_evict(cache_key)
	local bare_cache_key = cache_key:match("^%Z+%z[^/]+");
	local full_jid = cache_key:match("%z(.*)$");
	local jids = bare_cache[bare_cache_key];

	if jids then
		jids[full_jid] = nil;
	end
	if next(jids) == nil then
		bare_cache[bare_cache_key] = nil;
	end
end

local presence_cache = cache.new(cache_size, on_evict);

local function cache_hook(event)
	local origin, stanza = event.origin, event.stanza;
	local typ = stanza.attr.type;
	module:log("debug", "Cache hook, got %s from a %s", stanza:top_tag(), origin.type);
	if origin.type == "s2sin" and ( typ == nil or typ == "unavailable" ) then

		local contact_full = stanza.attr.from;
		local contact_bare = jid_bare(contact_full);
		local username, host = jid_split(stanza.attr.to);

		if not is_contact_subscribed(username, host, contact_bare) then
			module:log("debug", "Presence from jid not in roster");
			return;
		end

		local cache_key = username .. "\0" .. contact_full;
		local bare_cache_key = username .. "\0" .. contact_bare;
		local stamp = datetime.datetime();
		local jids = bare_cache[bare_cache_key];
		if jids then
			jids[contact_full] = stamp;
		else
			jids = { [contact_full] = stamp };
			bare_cache[bare_cache_key] = jids;
		end
		presence_cache:set(cache_key, true);
	end
end

module:hook("presence/bare", cache_hook, 10);
-- module:hook("presence/full", cache_hook, 10);

local function answer_probe_from_cache(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type ~= "probe" then return; end

	local username = origin.username;
	local contact_bare = stanza.attr.to;

	local bare_cache_key = username .. "\0" .. contact_bare;

	local cached = bare_cache[bare_cache_key];
	if not cached then return end
	for jid, stamp in pairs(cached) do
		local presence = st.presence({ to = origin.full_jid, from = jid })
			:tag("delay", { xmlns = "urn:xmpp:delay", from = module.host, stamp = stamp }):up();
		origin.send(presence);
	end
end

module:hook("pre-presence/bare", answer_probe_from_cache, 10);
