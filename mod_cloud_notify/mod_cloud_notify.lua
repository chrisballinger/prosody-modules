-- XEP-0357: Push (aka: My mobile OS vendor won't let me have persistent TCP connections)
-- Copyright (C) 2015-2016 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local st = require"util.stanza";
local jid = require"util.jid";
local dataform = require"util.dataforms".new;
local filters = require "util.filters";

local xmlns_push = "urn:xmpp:push:0";

-- configuration
local include_body = module:get_option_boolean("push_notification_with_body", false);
local include_sender = module:get_option_boolean("push_notification_with_sender", false);

-- For keeping state across reloads
local push_enabled = module:open_store();
-- TODO map store would be better here

-- http://xmpp.org/extensions/xep-0357.html#disco
module:hook("account-disco-info", function(event)
	(event.reply or event.stanza):tag("feature", {var=xmlns_push}):up();
end);

-- http://xmpp.org/extensions/xep-0357.html#enabling
module:hook("iq-set/self/"..xmlns_push..":enable", function (event)
	local origin, stanza = event.origin, event.stanza;
	local enable = stanza.tags[1];
	origin.log("debug", "Attempting to enable push notifications");
	-- MUST contain a 'jid' attribute of the XMPP Push Service being enabled
	local push_jid = enable.attr.jid;
	-- SHOULD contain a 'node' attribute
	local push_node = enable.attr.node;
	if not push_jid then
		origin.log("debug", "Push notification enable request missing the 'jid' field");
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Missing jid"));
		return true;
	end
	local publish_options = enable:get_child("x", "jabber:x:data");
	if not publish_options then
		-- Could be intentional
		origin.log("debug", "No publish options in request");
	end
	local user_push_services, rerr  = push_enabled:get(origin.username);
	if not user_push_services then
		if rerr then
			module:log("warn", "Error reading push notification storage: %s", rerr);
			origin.send(st.error_reply(stanza, "wait", "internal-server-error"));
			return true;
		end
		user_push_services = {};
	end
	user_push_services[push_jid .. "<" .. (push_node or "")] = {
		jid = push_jid;
		node = push_node;
		count = 0;
		options = publish_options and st.preserialize(publish_options);
	};
	local ok, err = push_enabled:set(origin.username, user_push_services);
	if not ok then
		origin.send(st.error_reply(stanza, "wait", "internal-server-error"));
	else
		origin.log("info", "Push notifications enabled");
		origin.send(st.reply(stanza));
	end
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
	local user_push_services = push_enabled:get(origin.username);
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
local function handle_notify_request(origin, stanza)
	local to = stanza.attr.to;
	local node = to and jid.split(to) or origin.username;
	local user_push_services = push_enabled:get(node);
	if not user_push_services then return end

	for _, push_info in pairs(user_push_services) do
		push_info.count = push_info.count + 1;
		local push_jid, push_node = push_info.jid, push_info.node;
		local push_publish = st.iq({ to = push_jid, from = node .. "@" .. module.host, type = "set", id = "push" })
			:tag("pubsub", { xmlns = "http://jabber.org/protocol/pubsub" })
				:tag("publish", { node = push_node })
					:tag("item")
						:tag("notification", { xmlns = xmlns_push });
		local form_data = {
			["message-count"] = tostring(push_info.count);
		};
		if include_sender then
			form_data["last-message-sender"] = stanza.attr.from;
		end
		if include_body then
			form_data["last-message-body"] = stanza:get_child_text("body");
		end
		push_publish:add_child(push_form:form(form_data));
		push_publish:up(); -- / notification
		push_publish:up(); -- / publish
		push_publish:up(); -- / pubsub
		if push_info.options then
			push_publish:tag("publish-options"):add_child(st.deserialize(push_info.options));
		end
		module:log("debug", "Sending push notification for %s@%s to %s", node, module.host, push_jid);
		module:send(push_publish);
	end
	push_enabled:set(node, user_push_services);
end

-- publish on offline message
module:hook("message/offline/handle", function(event)
	if event.stanza._notify then
		event.stanza._notify = nil;
		return;
	end
	return handle_notify_request(event.origin, event.stanza);
end, 1);

-- publish on unacked smacks message
local function process_new_stanza(stanza, session)
	if getmetatable(stanza) ~= st.stanza_mt then
		return stanza; -- Things we don't want to touch
	end
	if stanza.name == "message" and stanza.attr.xmlns == nil and
			( stanza.attr.type == "chat" or ( stanza.attr.type or "normal" ) == "normal" ) and
			-- not already notified via cloud
			not stanza._notify then
		stanza._notify = true;
		session.log("debug", "Invoking cloud handle_notify_request for new smacks hibernated stanza...");
		handle_notify_request(session, stanza)
	end
	return stanza;
end

-- smacks hibernation is started
local function hibernate_session(event)
	local session = event.origin;
	local queue = event.queue;
	-- process already unacked stanzas
	for i=1,#queue do
		process_new_stanza(queue[i], session);
	end
	-- process future unacked (hibernated) stanzas
	filters.add_filter(session, "stanzas/out", process_new_stanza);
end

-- smacks hibernation is ended
local function restore_session(event)
	local session = event.origin;
	filters.remove_filter(session, "stanzas/out", process_new_stanza);
end

module:hook("smacks-hibernation-start", hibernate_session);
module:hook("smacks-hibernation-end", restore_session);


module:hook("message/offline/broadcast", function(event)
	local origin = event.origin;
	local user_push_services = push_enabled:get(origin.username);
	if not user_push_services then return end

	for _, push_info in pairs(user_push_services) do
		if push_info then
			push_info.count = 0;
		end
	end
	push_enabled:set(origin.username, user_push_services);
end, 1);
