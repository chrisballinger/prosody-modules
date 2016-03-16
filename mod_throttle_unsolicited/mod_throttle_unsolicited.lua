local st = require"util.stanza";
local jid_split = require "util.jid".split;
local jid_bare = require "util.jid".bare;
local is_contact_subscribed = require "core.rostermanager".is_contact_subscribed;
local throttle = require "util.throttle";

local sessions = prosody.full_sessions;

local max = module:get_option_number("unsolicited_messages_per_minute", 10);
local multiplier = module:get_option_number("throttle_unsolicited_burst", 1);

function check_subscribed(event)
	local stanza, origin = event.stanza, event.origin;
	local log = origin.log or module._log;
	log("debug", "check_subscribed(%s)", stanza:top_tag());
	if stanza.attr.type == "error" then return end

	-- Check if it's a message to a joined room
	local to_bare = jid_bare(stanza.attr.to);
	local rooms = origin.rooms_joined;
	if rooms and rooms[to_bare] then
		log("debug", "Message to joined room, no limit");
		return
	end

	-- Retrieve or create throttle object
	local lim = origin.throttle_unsolicited;
	if not lim then
		log("debug", "New throttle");
		lim = throttle.create(max * multiplier, 60 * multiplier);
		origin.throttle_unsolicited = lim;
	end

	local to_user, to_host = jid_split(stanza.attr.to);
	local from_jid = jid_bare(stanza.attr.from);
	if to_user and not is_contact_subscribed(to_user, to_host, from_jid) then
		log("debug", "%s is not subscribed to %s@%s", from_jid, to_user, to_host);
		if not lim:poll(1) then
			log("warn", "Sent too many messages to non-contacts, bouncing message");
			event.origin.send(st.error_reply(stanza, "cancel", "service-unavailable"));
			return true;
		end
	end
end

module:hook("pre-message/bare", check_subscribed, 200);
module:hook("pre-message/full", check_subscribed, 200);

module:depends("track_muc_joins");
