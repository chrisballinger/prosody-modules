
-- Name arguments are unused here
-- luacheck: ignore 212

local definition_handlers = {};

local set = require"util.set";
local new_throttle = require "util.throttle".create;
local new_cache = require "util.cache".new;

local multirate_cache_size = module:get_option_number("firewall_multirate_cache_limit", 1000);

function definition_handlers.ZONE(zone_name, zone_members)
			local zone_member_list = {};
			for member in zone_members:gmatch("[^, ]+") do
				zone_member_list[#zone_member_list+1] = member;
			end
			return set.new(zone_member_list)._items;
end

-- Helper function used by RATE handler
local function evict_only_unthrottled(name, throttle)
	throttle:update();
	-- Check whether the throttle is at max balance (i.e. totally safe to forget about it)
	if throttle.balance < throttle.max then
		-- Not safe to forget
		return false;
	end
end

function definition_handlers.RATE(name, line)
			local rate = assert(tonumber(line:match("([%d.]+)")), "Unable to parse rate");
			local burst = tonumber(line:match("%(%s*burst%s+([%d.]+)%s*%)")) or 1;
			local max_throttles = tonumber(line:match("%(%s*entries%s+([%d]+)%s*%)")) or multirate_cache_size;

			local cache = new_cache(max_throttles, evict_only_unthrottled);

			return {
				single = function ()
					return new_throttle(rate*burst, burst);
				end;
				
				multi = function ()
					return {
						poll_on = function (_, key, amount)
							assert(key, "no key");
							local throttle = cache:get(key);
							if not throttle then
								throttle = new_throttle(rate*burst, burst);
								if not cache:set(key, throttle) then
									module:log("warn", "Multirate '%s' has hit its maximum number of active throttles (%d), denying new events", name, max_throttles);
									return false;
								end
							end
							return throttle:poll(amount);
						end;
					}
				end;
			};
end

return definition_handlers;
