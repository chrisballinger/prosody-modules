-- mod_profile

local st = require"util.stanza";
local jid_split = require"util.jid".split;
local jid_bare = require"util.jid".bare;
local is_admin = require"core.usermanager".is_admin;
local vcard = require"util.vcard";
local base64 = require"util.encodings".base64;
local sha1 = require"util.hashes".sha1;
local t_insert, t_remove = table.insert, table.remove;

local pep_plus;
if module:get_host_type() == "local" and module:get_option_boolean("vcard_to_pep", true) then
	pep_plus = module:depends"pep_plus";
end

local storage = module:open_store();
local legacy_storage = module:open_store("vcard");

local function get_item(vcard, name)
	local item;
	for i=1, #vcard do
		item=vcard[i];
		if item.name == name then
			return item, i;
		end
	end
end

local magic_mime = {
	["\137PNG\r\n\026\n"] = "image/png";
	["\255\216"] = "image/jpeg";
	["GIF87a"] = "image/gif";
	["GIF89a"] = "image/gif";
	["<?xml"] = "image/svg+xml";
}
local function identify(data)
	for magic, mime in pairs(magic_mime) do
		if data:sub(1, #magic) == magic then
			return mime;
		end
	end
	return "application/octet-stream";
end

local function update_pep(username, data, pep)
	pep = pep or pep_plus.get_pep_service(username.."@"..module.host);
	local photo, p = get_item(data, "PHOTO");
	if vcard.to_vcard4 then
		if p then t_remove(data, p); end
		pep:purge("urn:xmpp:vcard4", true);
		pep:publish("urn:xmpp:vcard4", true, "current", st.stanza("item", {id="current"})
			:add_child(vcard.to_vcard4(data)));
		if p then t_insert(data, p, photo); end
	end

	local nickname = get_item(data, "NICKNAME");
	if nickname and nickname[1] then
		pep:purge("http://jabber.org/protocol/nick", true);
		pep:publish("http://jabber.org/protocol/nick", true, "current", st.stanza("item", {id="current"})
			:tag("nick", { xmlns="http://jabber.org/protocol/nick" }):text(nickname[1]));
	end

	if photo and photo[1] then
		local photo_raw = base64.decode(photo[1]);
		local photo_hash = sha1(photo_raw, true);

		pep:purge("urn:xmpp:avatar:metadata", true);
		pep:purge("urn:xmpp:avatar:data", true);
		pep:publish("urn:xmpp:avatar:metadata", true, photo_hash, st.stanza("item", {id=photo_hash})
			:tag("metadata", { xmlns="urn:xmpp:avatar:metadata" })
				:tag("info", {
					bytes = tostring(#photo_raw),
					id = photo_hash,
					type = identify(photo_raw),
				}));
		pep:publish("urn:xmpp:avatar:data", true, photo_hash, st.stanza("item", {id=photo_hash})
			:tag("data", { xmlns="urn:xmpp:avatar:data" }):text(photo[1]));
	end
end

-- The "temporary" vCard XEP-0054 part
module:add_feature("vcard-temp");

local function handle_get(event)
	local origin, stanza = event.origin, event.stanza;
	local username = origin.username;
	local to = stanza.attr.to;
	if to then username = jid_split(to); end
	local data, err = storage:get(username);
	if not data then
		if err then
			origin.send(st.error_reply(stanza, "cancel", "internal-server-error", err));
			return true;
		end
		data = legacy_storage:get(username);
		data = data and st.deserialize(data);
		if data then
			origin.send(st.reply(stanza):add_child(data));
			return true;
		end
	end
	if not data then
		origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
		return true;
	end
	origin.send(st.reply(stanza):add_child(vcard.to_xep54(data)));
	return true;
end

local function handle_set(event)
	local origin, stanza = event.origin, event.stanza;
	local data = vcard.from_xep54(stanza.tags[1]);
	local username = origin.username;
	local to = stanza.attr.to;
	if to then
		if not is_admin(jid_bare(stanza.attr.from), module.host) then
			origin.send(st.error_reply(stanza, "auth", "forbidden"));
			return true;
		end
		username = jid_split(to);
	end
	local ok, err = storage:set(username, data);
	if not ok then
		origin.send(st.error_reply(stanza, "cancel", "internal-server-error", err));
		return true;
	end

	if pep_plus and username then
		update_pep(username, data);
	end

	origin.send(st.reply(stanza));
	return true;
end

module:hook("iq-get/bare/vcard-temp:vCard", handle_get);
module:hook("iq-get/host/vcard-temp:vCard", handle_get);

module:hook("iq-set/bare/vcard-temp:vCard", handle_set);
module:hook("iq-set/host/vcard-temp:vCard", handle_set);

local function on_publish(event)
	if event.actor == true then return end -- Not from a client
	local node, item = event.node, event.item;
	local username = jid_split(event.actor);
	local data = storage:get(username) or {};
	if node == "urn:xmpp:avatar:data" then
		local new_photo = item:get_child_text("data", "urn:xmpp:avatar:data");
		new_photo = new_photo and { name = "PHOTO"; ENCODING = { "b" }; new_photo } or nil;
		local _, i = get_item(data, "PHOTO")
		if new_photo then
			data[i or #data+1] = new_photo;
		elseif i then
			table.remove(data, i);
		end
	elseif node == "http://jabber.org/protocol/nick" then
		local new_nick = item:get_child_text("nick", "http://jabber.org/protocol/nick");
		new_nick = new_nick and new_nick ~= "" and { name = "NICKNAME"; new_nick } or nil;
		local _, i = get_item(data, "NICKNAME")
		if new_nick then
			data[i or #data+1] = new_nick;
		elseif i then
			table.remove(data, i);
		end
	else
		return;
	end
	storage:set(username, data);
end

local function pep_service_added(event)
	local item = event.item;
	local service, username = item.service, jid_split(item.jid);
	service.events.add_handler("item-published", on_publish);
	local data = storage:get(username);
	if data then
		update_pep(username, data, service);
	end
end

local function pep_service_removed()
	-- This would happen when mod_pep_plus gets unloaded, but this module gets unloaded before that
end

function module.load()
	module:handle_items("pep-service", pep_service_added, pep_service_removed, true);
end

-- The vCard4 part
if vcard.to_vcard4 then
	module:add_feature("urn:ietf:params:xml:ns:vcard-4.0");

	module:hook("iq-get/bare/urn:ietf:params:xml:ns:vcard-4.0:vcard", function(event)
		local origin, stanza = event.origin, event.stanza;
		local username = jid_split(stanza.attr.to) or origin.username;
		local data = storage:get(username);
		if not data then
			origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
			return true;
		end
		origin.send(st.reply(stanza):add_child(vcard.to_vcard4(data)));
		return true;
	end);

	if vcard.from_vcard4 then
		module:hook("iq-set/self/urn:ietf:params:xml:ns:vcard-4.0:vcard", function(event)
			local origin, stanza = event.origin, event.stanza;
			local ok, err = storage:set(origin.username, vcard.from_vcard4(stanza.tags[1]));
			if not ok then
				origin.send(st.error_reply(stanza, "cancel", "internal-server-error", err));
				return true;
			end
			origin.send(st.reply(stanza));
			return true;
		end);
	else
		module:hook("iq-set/self/urn:ietf:params:xml:ns:vcard-4.0:vcard", function(event)
			local origin, stanza = event.origin, event.stanza;
			origin.send(st.error_reply(stanza, "cancel", "feature-not-implemented"));
			return true;
		end);
	end
end

