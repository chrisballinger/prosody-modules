local t_insert = table.insert;

local mod_smacks = module:depends"smacks"

local function discard_unacked_messages(session)
	local queue = session.outgoing_stanza_queue;
	local replacement_queue = {};
	session.outgoing_stanza_queue = replacement_queue;

	for _, stanza in ipairs(queue) do
		if stanza.name == "message" and stanza.attr.xmlns == nil and
				( stanza.attr.type == "chat" or ( stanza.attr.type or "normal" ) == "normal" ) then
			-- do nothing here for normal messages and don't send out "message delivery errors",
			-- because messages are already in MAM at this point (no need to frighten users)
		else
			t_insert(replacement_queue, stanza);
		end
	end
end

local handle_unacked_stanzas = mod_smacks.handle_unacked_stanzas;

mod_smacks.handle_unacked_stanzas = function (session)
	-- Only deal with authenticated (c2s) sessions
	if session.username then
		discard_unacked_messages(session)
	end
	return handle_unacked_stanzas(session);
end

function module.unload()
	mod_smacks.handle_unacked_stanzas = handle_unacked_stanzas;
end
