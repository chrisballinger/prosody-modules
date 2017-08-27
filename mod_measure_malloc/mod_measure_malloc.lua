module:set_global();

local measure = require"core.statsmanager".measure;
local pposix = require"util.pposix";

local measures = {};
setmetatable(measures, {
	__index = function (t, k)
		local m = measure("sizes", "memory."..k); t[k] = m; return m;
	end
});
module:hook("stats-update", function ()
	local m = measures;
	for k, v in pairs(pposix.meminfo()) do
		m[k](v);
	end
end);
