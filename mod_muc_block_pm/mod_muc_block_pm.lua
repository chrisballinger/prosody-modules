local bare_jid = require"util.jid".bare;
local st = require"util.stanza";

local muc_rooms = module:depends"muc".rooms;

module:hook("message/full", function(event)
	local stanza, origin = event.stanza, event.origin;
	local to, from = stanza.attr.to, stanza.attr.from;
	local room = muc_rooms[bare_jid(to)];
	local to_occupant = room and room._occupants[to];
	local from_occupant = room and room._occupants[room._jid_nick[from]]
	if not ( to_occupant and from_occupant ) then return end

	if from_occupant.affiliation then
		to_occupant._pm_block_override = true;
	elseif not from_occupant._pm_block_override then
		origin.send(st.error_reply(stanza, "cancel", "not-authorized", "Private messages are disabled"));
		return true;
	end
end, 1);
