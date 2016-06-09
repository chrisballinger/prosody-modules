module:set_global();

local function sink_maker(config)
	local levels = {
		debug = measure("log.debug", "rate");
		info = measure("log.info", "rate");
		warn = measure("log.warn", "rate");
		error = measure("log.error", "rate");
	};
	return function (_, level)
		return levels[level]();
	end
end

require"core.loggingmanager".register_sink_type("measure", sink_maker);
