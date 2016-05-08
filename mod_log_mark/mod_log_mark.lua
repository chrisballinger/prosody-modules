module:set_global();

local log = _G.log;

module:add_timer(60-os.date("%S"), function ()
	log("info", "-- MARK --");
	return 60;
end);
