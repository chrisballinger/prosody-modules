local statsman = require "core.statsmanager";
local json = require "util.json";

local sessions = {};

local function updates_client_closed(response)
	module:log("debug", "Streamstats client closed");
	sessions[response] = nil;
end

local function get_updates(event)
	local request, response = event.request, event.response;

	response.on_destroy = updates_client_closed;

	response.conn:write(table.concat({
		"HTTP/1.1 200 OK";
		"Content-Type: text/event-stream";
		"X-Accel-Buffering: no"; -- For nginx maybe?
		"";
		"event: stats-full";
		"data: "..json.encode(statsman.get_stats());
		"";
		"";
	}, "\r\n"));

	sessions[response] = request;
	return true;
end


module:hook_global("stats-updated", function (event)
	local data = table.concat({
		"event: stats-updated";
		"data: "..json.encode(event.changed_stats);
		"";
		"";
	}, "\r\n")
	for response in pairs(sessions) do
		response.conn:write(data);
	end
end);


module:depends("http");
module:provides("http", {
	route = {
		GET = get_updates;
	}
});
