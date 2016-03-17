-- Copyright (C) 2010 Florian Zeitz
--
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

-- <session xmlns="http://prosody.im/streams/c2s" jid="alice@example.com/brussels">
--   <encrypted/>
--   <compressed/>
-- </session>

-- <session xmlns="http://prosody.im/streams/s2s" jid="example.com">
--   <encrypted>
--     <valid/> / <invalid/>
--   </encrypted>
--   <compressed/>
--   <in/> / <out/>
-- </session>

local st = require "util.stanza";
local uuid_generate = require "util.uuid".generate;
local is_admin = require "core.usermanager".is_admin;
local pubsub = require "util.pubsub";
local jid_bare = require "util.jid".bare;

local hosts = prosody.hosts;
local incoming_s2s = prosody.incoming_s2s;

module:set_global();

local service = {};

local xmlns_adminsub = "http://prosody.im/adminsub";
local xmlns_c2s_session = "http://prosody.im/streams/c2s";
local xmlns_s2s_session = "http://prosody.im/streams/s2s";

local idmap = {};

local function add_client(session, host)
	local name = session.full_jid;
	local id = idmap[name];
	if not id then
		id = uuid_generate();
		idmap[name] = id;
	end
	local item = st.stanza("item", { id = id }):tag("session", {xmlns = xmlns_c2s_session, jid = name}):up();
	if session.secure then
		local encrypted = item:tag("encrypted");
		local sock = session.conn and session.conn.socket and session.conn:socket()
		local info = sock and sock.info and sock:info();
		for k, v in pairs(info or {}) do
			encrypted:tag("info", { name = k }):text(tostring(v)):up();
		end
	end
	if session.compressed then
		item:tag("compressed"):up();
	end
	service[host]:publish(xmlns_c2s_session, host, id, item);
	module:log("debug", "Added client " .. name);
end

local function del_client(session, host)
	local name = session.full_jid;
	local id = idmap[name];
	if id then
		local notifier = st.stanza("retract", { id = id });
		service[host]:retract(xmlns_c2s_session, host, id, notifier);
	end
end

local function add_host(session, type, host)
	local name = (type == "out" and session.to_host) or (type == "in" and session.from_host);
	local id = idmap[name.."_"..type];
	if not id then
		id = uuid_generate();
		idmap[name.."_"..type] = id;
	end
	local item = st.stanza("item", { id = id }):tag("session", {xmlns = xmlns_s2s_session, jid = name})
		:tag(type):up();
	if session.secure then
		local encrypted = item:tag("encrypted");

		local sock = session.conn and session.conn.socket and session.conn:socket()
		local info = sock and sock.info and sock:info();
		for k, v in pairs(info or {}) do
			encrypted:tag("info", { name = k }):text(tostring(v)):up();
		end

		if session.cert_identity_status == "valid" then
			encrypted:tag("valid");
		else
			encrypted:tag("invalid");
		end
	end
	if session.compressed then
		item:tag("compressed"):up();
	end
	service[host]:publish(xmlns_s2s_session, host, id, item);
	module:log("debug", "Added host " .. name .. " s2s" .. type);
end

local function del_host(session, type, host)
	local name = (type == "out" and session.to_host) or (type == "in" and session.from_host);
	local id = idmap[name.."_"..type];
	if id then
		local notifier = st.stanza("retract", { id = id });
		service[host]:retract(xmlns_s2s_session, host, id, notifier);
	end
end

local function get_affiliation(jid, host)
	local bare_jid = jid_bare(jid);
	if is_admin(bare_jid, host) then
		return "member";
	else
		return "none";
	end
end

function module.add_host(module)
	-- Dependencies
	module:depends("bosh");
	module:depends("admin_adhoc");
	module:depends("http");
	local serve_file = module:depends("http_files").serve {
		path = module:get_directory() .. "/www_files";
	};

	-- Setup HTTP server
	module:provides("http", {
		name = "admin";
		route = {
			["GET"] = function(event)
				event.response.headers.location = event.request.path .. "/";
				return 301;
			end;
			["GET /*"] = serve_file;
		}
	});

	-- Setup adminsub service
	local function simple_broadcast(kind, node, jids, item)
		if item then
			item = st.clone(item);
			item.attr.xmlns = nil; -- Clear the pubsub namespace
		end
		local message = st.message({ from = module.host, type = "headline" })
			:tag("event", { xmlns = xmlns_adminsub .. "#event" })
				:tag(kind, { node = node })
					:add_child(item);
		for jid in pairs(jids) do
			module:log("debug", "Sending notification to %s", jid);
			message.attr.to = jid;
			module:send(message);
		end
	end

	service[module.host] = pubsub.new({
		broadcaster = simple_broadcast;
		normalize_jid = jid_bare;
		get_affiliation = function(jid) return get_affiliation(jid, module.host) end;
		capabilities = {
			member = {
				create = false;
				publish = false;
				retract = false;
				get_nodes = true;

				subscribe = true;
				unsubscribe = true;
				get_subscription = true;
				get_subscriptions = true;
				get_items = true;

				subscribe_other = false;
				unsubscribe_other = false;
				get_subscription_other = false;
				get_subscriptions_other = false;

				be_subscribed = true;
				be_unsubscribed = true;

				set_affiliation = false;
			};

			owner = {
				create = true;
				publish = true;
				retract = true;
				get_nodes = true;

				subscribe = true;
				unsubscribe = true;
				get_subscription = true;
				get_subscriptions = true;
				get_items = true;

				subscribe_other = true;
				unsubscribe_other = true;
				get_subscription_other = true;
				get_subscriptions_other = true;

				be_subscribed = true;
				be_unsubscribed = true;

				set_affiliation = true;
			};
		};
	});

	-- Create node for s2s sessions
	local ok, err = service[module.host]:create(xmlns_s2s_session, true);
	if not ok then
		module:log("warn", "Could not create node " .. xmlns_s2s_session .. ": " .. tostring(err));
	else
		service[module.host]:set_affiliation(xmlns_s2s_session, true, module.host, "owner")
	end

	-- Add outgoing s2s sessions
	for _, session in pairs(hosts[module.host].s2sout) do
		if session.type ~= "s2sout_unauthed" then
			add_host(session, "out", module.host);
		end
	end

	-- Add incomming s2s sessions
	for session in pairs(incoming_s2s) do
		if session.to_host == module.host then
			add_host(session, "in", module.host);
		end
	end

	-- Create node for c2s sessions
	ok, err = service[module.host]:create(xmlns_c2s_session, true);
	if not ok then
		module:log("warn", "Could not create node " .. xmlns_c2s_session .. ": " .. tostring(err));
	else
		service[module.host]:set_affiliation(xmlns_c2s_session, true, module.host, "owner")
	end

	-- Add c2s sessions
	for _, user in pairs(hosts[module.host].sessions or {}) do
		for _, session in pairs(user.sessions or {}) do
			add_client(session, module.host);
		end
	end

	-- Register adminsub handler
	module:hook("iq/host/http://prosody.im/adminsub:adminsub", function(event)
		local origin, stanza = event.origin, event.stanza;
		local adminsub = stanza.tags[1];
		local action = adminsub.tags[1];
		local reply;
		if action.name == "subscribe" then
			local ok, ret = service[module.host]:add_subscription(action.attr.node, stanza.attr.from, stanza.attr.from);
			if ok then
				reply = st.reply(stanza)
					:tag("adminsub", { xmlns = xmlns_adminsub });
			else
				reply = st.error_reply(stanza, "cancel", ret);
			end
		elseif action.name == "unsubscribe" then
			local ok, ret = service[module.host]:remove_subscription(action.attr.node, stanza.attr.from, stanza.attr.from);
			if ok then
				reply = st.reply(stanza)
					:tag("adminsub", { xmlns = xmlns_adminsub });
			else
				reply = st.error_reply(stanza, "cancel", ret);
			end
		elseif action.name == "items" then
			local node = action.attr.node;
			local ok, ret = service[module.host]:get_items(node, stanza.attr.from);
			if not ok then
				origin.send(st.error_reply(stanza, "cancel", ret));
				return true;
			end

			local data = st.stanza("items", { node = node });
			for _, entry in pairs(ret) do
				data:add_child(entry);
			end
			if data then
				reply = st.reply(stanza)
					:tag("adminsub", { xmlns = xmlns_adminsub })
						:add_child(data);
			else
				reply = st.error_reply(stanza, "cancel", "item-not-found");
			end
		elseif action.name == "adminfor" then
			local data = st.stanza("adminfor");
			for host_name in pairs(hosts) do
				if is_admin(stanza.attr.from, host_name) then
					data:tag("item"):text(host_name):up();
				end
			end
			reply = st.reply(stanza)
				:tag("adminsub", { xmlns = xmlns_adminsub })
					:add_child(data);
		else
			reply = st.error_reply(stanza, "feature-not-implemented");
		end
		origin.send(reply);
		return true;
	end);

	-- Add/remove c2s sessions
	module:hook("resource-bind", function(event)
		add_client(event.session, module.host);
	end);

	module:hook("resource-unbind", function(event)
		del_client(event.session, module.host);
		service[module.host]:remove_subscription(xmlns_c2s_session, module.host, event.session.full_jid);
		service[module.host]:remove_subscription(xmlns_s2s_session, module.host, event.session.full_jid);
	end);

	-- Add/remove s2s sessions
	module:hook("s2sout-established", function(event)
		add_host(event.session, "out", module.host);
	end);

	module:hook("s2sin-established", function(event)
		add_host(event.session, "in", module.host);
	end);

	module:hook("s2sout-destroyed", function(event)
		del_host(event.session, "out", module.host);
	end);

	module:hook("s2sin-destroyed", function(event)
		del_host(event.session, "in", module.host);
	end);
end
