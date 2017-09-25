module:set_global();

local traceback = require "util.debug".traceback;

require"util.signal".signal(module:get_option_string(module.name, "SIGUSR1"), function ()
	module:log("info", "Received SIGUSR1, writing traceback");
	local f = io.open(prosody.paths.data.."/traceback.txt", "a+");
	f:write(traceback(), "\n");
	f:close();
end);

