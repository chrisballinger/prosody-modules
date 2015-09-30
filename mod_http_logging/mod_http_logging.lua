-- mod_http_logging
--
-- Copyright (C) 2015 Kim Alvefur
--
-- Produces HTTP logs in the style of Apache
--
-- TODO
-- * Configurable format?

module:set_global();

local server = require "net.http.server";

local send_response = server.send_response;
local function log_and_send_response(response, body)
	if not response.finished then
		body = body or response.body;
		local len = body and #body or "-";
		local request = response.request;
		local ip = request.conn:ip();
		local req = string.format("%s %s HTTP/%s", request.method, request.path, request.httpversion);
		local date = os.date("%d/%m/%Y:%H:%M:%S %z");
		module:log("info", "%s - - [%s] \"%s\" %d %s", ip, date, req, response.status_code, tostring(len));
	end
	return server.send_response(response, body);
end

if module.wrap_object_event then
	-- Use object event wrapping, allows clean unloading of the module
	module:wrap_object_event(server._events, false, function (handlers, event_name, event_data)
		if event_data.response then
			event_data.response.send = log_and_send_response;
		end
		return handlers(event_name, event_data);
	end);
else
	-- Fall back to monkeypatching, unlikely to behave nicely in the
	-- presence of other modules also doing this
	server.send_response = log_and_send_response;
	function module.unload()
		server.send_response = send_response;
	end
end
