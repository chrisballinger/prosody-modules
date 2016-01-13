-- Module to block all outgoing stanzas from a list of users

local jid_bare = require "util.jid".bare;
local is_admin = require "core.usermanager".is_admin;

local block_users = module:get_option_set("block_outgoing_users", {});
local block_all = block_users:empty();

local stanza_types = { "iq", "presence", "message" };
local jid_types = { "host", "bare", "full" };

local function block_stanza(event)
	local stanza = event.stanza;
	local from_jid = jid_bare(stanza.attr.from);
	if stanza.attr.to == nil or is_admin(from_jid, module.host) then
		return;
	end
	if block_all or block_users:contains(from_jid)  then
		module:log("debug", "Blocked outgoing %s stanza from %s", stanza.name, stanza.attr.from);
		return true;
	end
end

function module.load()
	for _, stanza_type in ipairs(stanza_types) do
		for _, jid_type in ipairs(jid_types) do
			module:hook("pre-"..stanza_type.."/"..jid_type, block_stanza, 10000);
		end
	end
end
