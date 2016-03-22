-- Fetches Atom feeds and publishes to PubSub nodes
--
-- Config:
-- Component "pubsub.example.com" "pubsub"
-- modules_enabled = {
--   "pubsub_feeds";
-- }
-- feeds = { -- node -> url
--   prosody_blog = "http://blog.prosody.im/feed/atom.xml";
-- }
-- feed_pull_interval = 20 -- minutes
--
-- Reference
-- http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.4.html

local pubsub = module:depends"pubsub";

local date, time = os.date, os.time;
local dt_parse, dt_datetime = require "util.datetime".parse, require "util.datetime".datetime;
local uuid = require "util.uuid".generate;
local hmac_sha1 = require "util.hashes".hmac_sha1;
local parse_xml = require "util.xml".parse;
local st = require "util.stanza";
local translate_rss = module:require("feeds").translate_rss;

local xmlns_atom = "http://www.w3.org/2005/Atom";

local function parse_feed(data)
	local feed, err = parse_xml(data);
	if not feed then return feed, err; end
	if feed.attr.xmlns == xmlns_atom then
		return feed;
	elseif feed.attr.xmlns == nil and feed.name == "rss" then
		return translate_rss(feed);
	end
	return nil, "unsupported-format";
end

local use_pubsubhubub = module:get_option_boolean("use_pubsubhubub", true);
if use_pubsubhubub then
	module:depends"http";
end

local http = require "net.http";
local formdecode = http.formdecode;
local formencode = http.formencode;

local feed_list = module:shared("feed_list");
local refresh_interval;

function module.load()
	local config = module:get_option("feeds") or {
		planet_jabber = "http://planet.jabber.org/atom.xml";
		prosody_blog = "http://blog.prosody.im/feed/atom.xml";
	};
	refresh_interval = module:get_option_number("feed_pull_interval", 15) * 60;
	local ok, nodes = pubsub.service:get_nodes(true);
	if not ok then nodes = {}; end
	local new_feed_list = {};
	for node, url in pairs(config) do
		if type(node) == "number" then
			node = url;
		end
		new_feed_list[node] = true;
		if not feed_list[node] then
			feed_list[node] = { url = url; node = node; last_update = 0 };
		else
			feed_list[node].url = url;
		end
		if not nodes[node] then
			feed_list[node].last_update = 0;
		end
	end
	for node in pairs(feed_list) do
		if not new_feed_list[node] then
			feed_list[node] = nil;
		end
	end
end

function update_entry(item)
	local node = item.node;
	module:log("debug", "parsing %d bytes of data in node %s", #item.data or 0, node)
	local feed = parse_feed(item.data);
	for entry in feed:childtags("entry") do
		entry.attr.xmlns = xmlns_atom;

		local e_published = entry:get_child_text("published");
		e_published = e_published and dt_parse(e_published);
		local e_updated = entry:get_child_text("updated");
		e_updated = e_updated and dt_parse(e_updated);

		local timestamp = e_updated or e_published or nil;
		--module:log("debug", "timestamp is %s, item.last_update is %s", tostring(timestamp), tostring(item.last_update));
		if not timestamp or not item.last_update or timestamp > item.last_update then
			local id = entry:get_child_text("id");
			id = id or item.url.."#"..dt_datetime(timestamp); -- Missing id, so make one up
			local xitem = st.stanza("item", { id = id }):add_child(entry);
			-- TODO Put data from /feed into item/source

			--module:log("debug", "publishing to %s, id %s", node, id);
			local ok, err = pubsub.service:publish(node, true, id, xitem);
			if not ok then
				if err == "item-not-found" then -- try again
					--module:log("debug", "got item-not-found, creating %s and trying again", node);
					local ok, err = pubsub.service:create(node, true);
					if not ok then
						module:log("error", "could not create node %s: %s", node, err);
						return;
					end
					local ok, err = pubsub.service:publish(node, true, id, xitem);
					if not ok then
						module:log("error", "could not create or publish node %s: %s", node, err);
						return
					end
				else
					module:log("error", "publishing %s failed: %s", node, err);
				end
			end
		end
	end

	if item.lease_expires and item.lease_expires > time() then
		item.subscription = nil;
		item.lease_expires = nil;
	end
	if use_pubsubhubub and not item.subscription then
		--module:log("debug", "check if %s has a hub", item.node);
		for link in feed:childtags("link") do
			if link.attr.rel == "hub" then
				item.hub = link.attr.href;
				module:log("debug", "Node %s has a hub: %s", item.node, item.hub);
				return subscribe(item);
			end
		end
	end
end

function fetch(item, callback) -- HTTP Pull
	local headers = { };
	if item.data and item.last_update then
		headers["If-Modified-Since"] = date("!%a, %d %b %Y %H:%M:%S %Z", item.last_update);
	end
	http.request(item.url, { headers = headers }, function(data, code)
		if code == 200 then
			item.data = data;
			if callback then callback(item) end
			item.last_update = time();
		elseif code == 304 then
			item.last_update = time();
		end
	end);
end

function refresh_feeds(now)
	--module:log("debug", "Refreshing feeds");
	for _, item in pairs(feed_list) do
		if item.subscription ~= "subscribe" and item.last_update + refresh_interval < now then
			--module:log("debug", "checking %s", item.node);
			fetch(item, update_entry);
		end
	end
	return refresh_interval;
end

local function format_url(node)
	return module:http_url(nil, "/callback") .. "?" .. formencode({ node = node });
end

function subscribe(feed, want)
	want = want or "subscribe";
	feed.secret = feed.secret or uuid();
	local body = formencode{
		["hub.callback"] = format_url(feed.node);
		["hub.mode"] = want;
		["hub.topic"] = feed.url;
		["hub.verify"] = "async"; -- COMPAT this is REQUIRED in the 0.3 draft but removed in 0.4
		["hub.secret"] = feed.secret;
		--["hub.lease_seconds"] = "";
	};

	--module:log("debug", "subscription request, body: %s", body);

	--FIXME The subscription states and related stuff
	feed.subscription = want;
	http.request(feed.hub, { body = body }, function(data, code)
		module:log("debug", "subscription to %s submitted, status %s", feed.node, tostring(code));
		if code >= 400 then
			module:log("error", "There was something wrong with our subscription request, body: %s", tostring(data));
			feed.subscription = "failed";
		end
	end);
end

function handle_http_request(event)
	local request = event.request;
	local method = request.method;
	local body = request.body;

	--module:log("debug", "%s request to %s%s with body %s", method, request.url.path, request.url.query and "?" .. request.url.query or "", #body > 0 and body or "empty");
	local query = request.url.query or {}; --FIXME
	if query and type(query) == "string" then
		query = formdecode(query);
		--module:log("debug", "GET data: %s", dump(query));
	end
	--module:log("debug", "Headers: %s", dump(request.headers));

	local feed = feed_list[query.node];
	if not feed then
		return 404;
	end

	if method == "GET" then
		if query.node then
			if query["hub.topic"] ~= feed.url then
				module:log("debug", "Invalid topic: %s", tostring(query["hub.topic"]))
				return 404
			end
			if query["hub.mode"] == "denied" then
				module:log("info", "Subscription denied: %s", tostring(query["hub.reason"] or "No reason given"))
				feed.subscription = "denied";
				return "Ok then :(";
			elseif query["hub.mode"] == feed.subscription then
				module:log("debug", "Confirming %s request to %s", feed.subscription, feed.url)
			else
				module:log("debug", "Invalid mode: %s", tostring(query["hub.mode"]))
				return 400
			end
			local lease_seconds = tonumber(query["hub.lease_seconds"]);
			if lease_seconds then
				feed.lease_expires = time() + lease_seconds - refresh_interval * 2;
			end
			return query["hub.challenge"];
		end
		return 400;
	elseif method == "POST" then
		if #body > 0 then
			module:log("debug", "got %d bytes PuSHed for %s", #body, query.node);
			local signature = request.headers.x_hub_signature;
			if feed.secret then
				local localsig = "sha1=" .. hmac_sha1(feed.secret, body, true);
				if localsig ~= signature then
					module:log("debug", "Invalid signature, got %s but wanted %s", tostring(signature), tostring(localsig));
					return 401;
				end
				module:log("debug", "Valid signature");
			end
			feed.data = body;
			update_entry(feed);
			feed.last_update = time();
			return 202;
		end
		return 400;
	end
	return 501;
end

if use_pubsubhubub then
	module:provides("http", {
		default_path = "/callback";
		route = {
			GET = handle_http_request;
			POST = handle_http_request;
			-- This all?
		};
	});
end

module:add_timer(1, refresh_feeds);
