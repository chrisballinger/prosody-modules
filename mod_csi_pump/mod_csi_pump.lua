-- Copyright (C) 2016 Kim Alvefur
--

module:depends"csi"
module:depends"track_muc_joins"
local jid = require "util.jid";
local new_queue = require "util.queue".new;

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
	function q:flush()
		local item = self:pop();
		while item do
			output(item, self);
			item = self:pop();
		end
		return true;
	end
	return q;
end

-- TODO delay stamps
-- local dt = require "util.datetime";

local function is_important(stanza, session)
	local st_name = stanza.name;
	if not st_name then return false; end
	local st_type = stanza.attr.type;
	if st_name == "presence" then
		-- TODO check for MUC status codes?
		return false;
	elseif st_name == "message" then
		if st_type == "headline" then
			return false;
		end
		local body = stanza:get_child_text("body");
		if not body then return false; end
		if st_type == "groupchat" then
			if body:find(session.username, 1, true) then return true; end
			local rooms = session.rooms_joined;
			if not rooms then return false; end
			local room_nick = rooms[jid.bare(stanza.attr.from)];
			if room_nick and body:find(room_nick, 1, true) then return true; end
			return false;
		end
		return body;
	end
	return true;
end

module:hook("csi-client-inactive", function (event)
	local session = event.origin;
	if session.pump then
		session.pump:pause();
	else
		session._orig_send = session.send;
		local pump = new_pump(session.send, 100);
		pump:pause();
		session.pump = pump;
		function session.send(stanza)
			pump:push(stanza);
			if is_important(stanza, session) then
				pump:flush();
			end
			return true;
		end
	end
end);

module:hook("csi-client-active", function (event)
	local session = event.origin;
	if session.pump then
		session.pump:resume();
	end
end);

