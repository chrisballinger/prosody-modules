module:set_global();

local measure = require"core.statsmanager".measure;

local function sink_maker(config)
	local levels = {
		debug = measure("rate", "log.debug");
		info = measure("rate", "log.info");
		warn = measure("rate", "log.warn");
		error = measure("rate", "log.error");
	};
	return function (_, level)
		return levels[level]();
	end
end

require"core.loggingmanager".register_sink_type("measure", sink_maker);
