
module:hook("presence/full", function (event)
	local stanza = event.stanza;
	local session = sessions[stanza.attr.to];
	if not session then return end;
	local log = session.log or module._log;
	local muc_x = stanza:get_child("x", "http://jabber.org/protocol/muc#user");
	if not muc_x then return end -- Not MUC related

	local room = jid_bare(stanza.attr.from);
	local joined = stanza.attr.type;
	if joined == nil then
		joined = true;
	elseif joined == "unavailable" then
		joined = nil;
	else
		-- Ignore errors and whatever
		return;
	end

	-- Check for status code 100, meaning it's their own reflected presence
	for status in muc_x:childtags("status") do
		log("debug", "Status code %d", status.attr.code);
		if status.attr.code == "110" then
			log("debug", "%s room %s", joined and "Joined" or "Left", room);
			local rooms = session.rooms_joined;
			if not rooms then
				session.rooms_joined = { [room] = joined };
			else
				rooms[room] = joined;
			end
			return;
		end
	end
end);

-- TODO Check session.directed for outgoing presence?