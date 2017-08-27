-- Copyright (C) 2016 Kim Alvefur
-- Copyright (C) 2017 Thilo Molitor
--

local filter_muc = module:get_option_boolean("csi_battery_saver_filter_muc", false);

module:depends"csi"
if filter_muc then module:depends"track_muc_joins"; end		-- only depend on this module if we actually use it
local s_match = string.match;
local s_sub = string.sub;
local jid = require "util.jid";
local new_queue = require "util.queue".new;
local datetime = require "util.datetime";
local st = require "util.stanza";

local xmlns_delay = "urn:xmpp:delay";

-- a log id for this module instance
local id = s_sub(require "util.hashes".sha256(datetime.datetime(), true), 1, 4);


-- Patched version of util.stanza:find() that supports giving stanza names
-- without their namespace, allowing for every namespace.
local function find(self, path)
	local pos = 1;
	local len = #path + 1;

	repeat
		local xmlns, name, text;
		local char = s_sub(path, pos, pos);
		if char == "@" then
			return self.attr[s_sub(path, pos + 1)];
		elseif char == "{" then
			xmlns, pos = s_match(path, "^([^}]+)}()", pos + 1);
		end
		name, text, pos = s_match(path, "^([^@/#]*)([/#]?)()", pos);
		name = name ~= "" and name or nil;
		if pos == len then
			if text == "#" then
				local child = xmlns ~= nil and self:get_child(name, xmlns) or self:child_with_name(name);
				return child and child:get_text() or nil;
			end
			return xmlns ~= nil and self:get_child(name, xmlns) or self:child_with_name(name);
		end
		self = xmlns ~= nil and self:get_child(name, xmlns) or self:child_with_name(name);
	until not self
	return nil;
end

local function new_pump(output, ...)
	-- luacheck: ignore 212/self
	local q = new_queue(...);
	local flush = true;
	function q:pause()
		flush = false;
	end
	function q:resume()
		flush = true;
		return q:flush();
	end
	local push = q.push;
	function q:push(item)
		local ok = push(self, item);
		if not ok then
			q:flush();
			output(item, self);
		elseif flush then
			return q:flush();
		end
		return true;
	end
	function q:flush(alternative_output)
		local out = alternative_output or output;
		local item = self:pop();
		while item do
			out(item, self);
			item = self:pop();
		end
		return true;
	end
	return q;
end

local function is_stamp_needed(stanza, session)
	local st_name = stanza and stanza.name or nil;
	if st_name == "presence" then
		return true;
	elseif st_name == "message" then
		if stanza:get_child("delay", xmlns_delay) then return false; end
		if stanza.attr.type == "chat" or stanza.attr.type == "groupchat" then return true; end
	end
	return false;
end

local function add_stamp(stanza, session)
	stanza = stanza:tag("delay", { xmlns = xmlns_delay, from = session.host, stamp = datetime.datetime()});
	return stanza;
end

local function is_important(stanza, session)
	local st_name = stanza and stanza.name or nil;
	if not st_name then return true; end	-- nonzas are always important
	if st_name == "presence" then
		-- TODO check for MUC status codes?
		return false;
	elseif st_name == "message" then
		-- unpack carbon copies
		local stanza_direction = "in";
		local carbon;
		local st_type;
		-- support carbon copied message stanzas having an arbitrary message-namespace or no message-namespace at all
		if not carbon then carbon = find(stanza, "{urn:xmpp:carbons:2}/forwarded/message"); end
		if not carbon then carbon = find(stanza, "{urn:xmpp:carbons:1}/forwarded/message"); end
		stanza_direction = carbon and stanza:child_with_name("sent") and "out" or "in";
		--session.log("debug", "mod_csi_battery_saver(%s): stanza_direction = %s, carbon = %s, stanza = %s", id, stanza_direction, carbon and "true" or "false", tostring(stanza));
		if carbon then stanza = carbon; end
		st_type = stanza.attr.type;
		
		-- headline message are always not important
		if st_type == "headline" then return false; end
		
		-- chat markers (XEP-0333) are important, too, because some clients use them to update their notifications
		if find(stanza, "{urn:xmpp:chat-markers:0}") then return true; end;
		
		-- carbon copied outgoing messages are important (some clients update their notifications upon receiving those) --> don't return false here
		--if carbon and stanza_direction == "out" then return false; end
		
		-- We can't check for body contents in encrypted messages, so let's treat them as important
		-- Some clients don't even set a body or an empty body for encrypted messages
		
		-- check omemo https://xmpp.org/extensions/inbox/omemo.html
		if stanza:get_child("encrypted", "eu.siacs.conversations.axolotl") or stanza:get_child("encrypted", "urn:xmpp:omemo:0") then return true; end
		
		-- check xep27 pgp https://xmpp.org/extensions/xep-0027.html
		if stanza:get_child("x", "jabber:x:encrypted") then return true; end
		
		-- check xep373 pgp (OX) https://xmpp.org/extensions/xep-0373.html
		if stanza:get_child("openpgp", "urn:xmpp:openpgp:0") then return true; end
		
		local body = stanza:get_child_text("body");
		if st_type == "groupchat" then
			if stanza:get_child_text("subject") then return true; end
			if body == nil or body == "" then return false; end
			-- body contains text, let's see if we want to process it further
			if filter_muc then
				if body:find(session.username, 1, true) then return true; end
				local rooms = session.rooms_joined;
				if not rooms then return false; end
				local room_nick = rooms[jid.bare(stanza_direction == "in" and stanza.attr.from or stanza.attr.to)];
				if room_nick and body:find(room_nick, 1, true) then return true; end
				return false;
			else
				return true;
			end
		end
		return body ~= nil and body ~= "";
	end
	return true;
end

module:hook("csi-client-inactive", function (event)
	local session = event.origin;
	if session.pump then
		session.log("debug", "mod_csi_battery_saver(%s): Client is inactive, buffering unimportant outgoing stanzas", id);
		session.pump:pause();
	else
		session.log("debug", "mod_csi_battery_saver(%s): Client is inactive the first time, initializing module for this session", id);
		local pump = new_pump(session.send, 100);
		pump:pause();
		session.pump = pump;
		session._pump_orig_send = session.send;
		function session.send(stanza)
			session.log("debug", "mod_csi_battery_saver(%s): Got outgoing stanza: <%s>", id, tostring(stanza.name or stanza));
			local important = is_important(stanza, session);
			-- clone stanzas before adding delay stamp and putting them into the queue
			if st.is_stanza(stanza) then stanza = st.clone(stanza); end
			-- add delay stamp to unimportant (buffered) stanzas that can/need be stamped
			if not important and is_stamp_needed(stanza, session) then stanza = add_stamp(stanza, session); end
			-- add stanza to outgoing queue and flush the buffer if needed
			pump:push(stanza);
			if important then
				session.log("debug", "mod_csi_battery_saver(%s): Encountered important stanza, flushing buffer: <%s>", id, tostring(stanza.name or stanza));
				pump:flush();
			end
			return true;
		end
	end
end);

module:hook("csi-client-active", function (event)
	local session = event.origin;
	if session.pump then
		session.log("debug", "mod_csi_battery_saver(%s): Client is active, resuming direct delivery", id);
		session.pump:resume();
	end
end);

-- clean up this session on hibernation start
module:hook("smacks-hibernation-start", function (event)
	local session = event.origin;
	if session.pump then
		session.log("debug", "mod_csi_battery_saver(%s): Hibernation started, flushing buffer and afterwards disabling for this session", id);
		session.pump:flush();
		session.send = session._pump_orig_send;
		session.pump = nil;
		session._pump_orig_send = nil;
	end
end);

-- clean up this session on hibernation end as well
-- but don't change resumed.send(), it is already overwritten with session.send() by the smacks module
module:hook("smacks-hibernation-end", function (event)
	local session = event.resumed;
	if session.pump then
		session.log("debug", "mod_csi_battery_saver(%s): Hibernation ended without being started, flushing buffer and afterwards disabling for this session", id);
		session.pump:flush(session.send);		-- use the fresh session.send() introduced by the smacks resume
		-- don't reset session.send() because this is not the send previously overwritten by this module, but a fresh one
		-- session.send = session._pump_orig_send;
		session.pump = nil;
		session._pump_orig_send = nil;
	end
end);

function module.unload()
	module:log("info", "%s: Unloading module, flushing all buffers", id);
	local host_sessions = prosody.hosts[module.host].sessions;
	for _, user in pairs(host_sessions) do
		for _, session in pairs(user.sessions) do
			if session.pump then
				session.log("debug", "mod_csi_battery_saver(%s): Flushing buffer and restoring to original session.send()", id);
				session.pump:flush();
				session.send = session._pump_orig_send;
				session.pump = nil;
				session._pump_orig_send = nil;
			end
		end
	end
end

module:log("info", "%s: Successfully loaded module", id);
