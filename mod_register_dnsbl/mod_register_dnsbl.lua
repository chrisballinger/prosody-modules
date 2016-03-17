local adns = require "net.adns";
local rbl = module:get_option_string("registration_rbl");

local function reverse(ip, suffix)
	local a,b,c,d = ip:match("^(%d+%).(%d+%).(%d+%).(%d+%)$");
	if not a then return end
	return ("%d.%d.%d.%d.%s"):format(d,c,b,a, suffix);
end

-- TODO async
-- module:hook("user-registering", function (event) end);

module:hook("user-registered", function (event)
	local session = event.session;
	local ip = session and session.ip;
	local rbl_ip = ip and reverse(ip, rbl);
	if rbl_ip then
		local log = session.log;
		adns.lookup(function (reply)
			if reply and reply[1] then
				log("warn", "Registration from IP %s found in RBL", ip);
			end
		end, rbl_ip);
	end
end);
