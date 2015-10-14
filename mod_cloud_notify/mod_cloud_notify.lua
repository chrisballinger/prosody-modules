-- XEP-0357: Push (aka: My mobile OS vendor won't let me have persistent TCP connections)
-- Copyright (C) 2015 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local st = require"util.stanza";
local jid = require"util.jid";
local dataform = require"util.dataforms".new;

local xmlns_push = "urn:xmpp:push:0";

module:add_feature(xmlns_push);

local push_enabled = module:shared("push-enabled-users");

-- http://xmpp.org/extensions/xep-0357.html#enabling
module:hook("iq-set/self/"..xmlns_push..":enable", function (event)
	local origin, stanza = event.origin, event.stanza;
	-- MUST contain a 'jid' attribute of the XMPP Push Service being enabled
	local push_jid = stanza.tags[1].attr.jid;
	-- SHOULD contain a 'node' attribute
	local push_node = stanza.tags[1].attr.node;
	if not push_jid then
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Missing jid"));
		return true;
	end
	local publish_options = stanza.tags[1].tags[1];
	if publish_options and ( publish_options.name ~= "x" or publish_options.attr.xmlns ~= "jabber:x:data" ) then
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid publish options"));
		return true;
	end
	local user_push_services = push_enabled[origin.username];
	if not user_push_services then
		user_push_services = {};
	end
	user_push_services[push_jid .. "<" .. (push_node or "")] = {
		jid = push_jid;
		node = push_node;
		count = 0;
		options = publish_options;
	};
	origin.send(st.reply(stanza));
	return true;
end);

-- http://xmpp.org/extensions/xep-0357.html#disabling
module:hook("iq-set/self/"..xmlns_push..":disable", function (event)
	local origin, stanza = event.origin, event.stanza;
	local push_jid = stanza.tags[1].attr.jid; -- MUST include a 'jid' attribute
	local push_node = stanza.tags[1].attr.node; -- A 'node' attribute MAY be included
	if not push_jid then
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Missing jid"));
		return true;
	end
	local user_push_services = push_enabled[origin.username];
	for key, push_info in pairs(user_push_services) do
		if push_info.jid == push_jid and (not push_node or push_info.node == push_node) then
			user_push_services[key] = nil;
		end
	end
	origin.send(st.reply(stanza));
	return true;
end);

local push_form = dataform {
	{ name = "FORM_TYPE"; type = "hidden"; value = "urn:xmpp:push:summary"; };
	{ name = "message-count"; type = "text-single"; };
	{ name = "pending-subscription-count"; type = "text-single"; };
	{ name = "last-message-sender"; type = "jid-single"; };
	{ name = "last-message-body"; type = "text-single"; };
};

-- http://xmpp.org/extensions/xep-0357.html#publishing
module:hook("message/offline/handle", function(event)
	local origin, stanza = event.origin, event.stanza;
	local to = stanza.attr.to;
	local node = to and jid.split(to) or origin.username;
	local user_push_services = push_enabled[node];
	if not user_push_services then return end

	for _, push_info in pairs(user_push_services) do
		push_info.count = push_info.count + 1;
		local push_jid, push_node = push_info.jid, push_info.node;
		local push_publish = st.iq({ to = push_jid, from = module.host, type = "set", id = "push" })
			:tag("pubsub", { xmlns = "http://jabber.org/protocol/pubsub" })
				:tag("publish", { node = push_node });
		push_publish:add_child(push_form:form({
			["message-count"] = tostring(push_info.count);
			["last-message-sender"] = stanza.attr.from;
			["last-message-body"] = stanza:get_child_text("body");
		}));
		push_publish:up(); -- / publish
		if push_info.options then
			push_publish:tag("publish-options"):add_child(push_info.options);
		end
		module:send(push_publish);
	end
end, 1);

module:hook("message/offline/broadcast", function(event)
	local user_push_services = push_enabled[event.origin.username];
	if not user_push_services then return end

	for _, push_info in pairs(user_push_services) do
		if push_info then
			push_info.count = 0;
		end
	end
end, 1);
