-- mod_conversejs
-- Copyright (C) 2017 Kim Alvefur

local json_encode = require"util.json".encode;

module:depends"bosh";

local has_ws = pcall(function ()
	module:depends("websocket");
end);

local template = [[
<!DOCTYPE html>
<meta charset="utf-8">
<link rel="stylesheet" type="text/css" media="screen" href="https://cdn.conversejs.org/css/converse.min.css">
<script src="https://cdn.conversejs.org/dist/converse.min.js"></script>
<body><script>converse.initialize(%s);</script>
]]

module:provides("http", {
	route = {
		GET = function (event)
			event.response.headers.content_type = "text/html";
			return template:format(json_encode({
				-- debug = true,
				bosh_service_url = module:http_url("bosh","/http-bind");
				websocket_url = has_ws and module:http_url("websocket","xmpp-websocket"):gsub("^http", "ws") or nil;
				authentication = module:get_option_string("authentication") == "anonymous" and "anonymous" or "login";
			}));
		end;
	}
});

