
-- Name arguments are unused here
-- luacheck: ignore 212

local definition_handlers = {};

local http = require "net.http";
local timer = require "util.timer";
local set = require"util.set";
local new_throttle = require "util.throttle".create;

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
			local deny_when_full = not line:match("%(allow overflow%)");
			return {
				single = function ()
					return new_throttle(rate*burst, burst);
				end;
				
				multi = function ()
					local cache = require "util.cache".new(max_throttles, deny_when_full and evict_only_unthrottled or nil);
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

local list_backends = {
	memory = {
		init = function (self, type, opts)
			if opts.limit then
				local have_cache_lib, cache_lib = pcall(require, "util.cache");
				if not have_cache_lib then
					error("In-memory lists with a size limit require Prosody 0.10");
				end
				self.cache = cache_lib.new((assert(tonumber(opts.limit), "Invalid list limit")));
				if not self.cache.table then
					error("In-memory lists with a size limit require a newer version of Prosody 0.10");
				end
				self.items = self.cache:table();
			else
				self.items = {};
			end
		end;
		add = function (self, item)
			self.items[item] = true;
		end;
		remove = function (self, item)
			self.items[item] = nil;
		end;
		contains = function (self, item)
			return self.items[item] == true;
		end;
	};
	http = {
		init = function (self, url, opts)
			local poll_interval = assert(tonumber(opts.ttl or "3600"), "invalid ttl for <"..url.."> (expected number of seconds)");
			local pattern = opts.pattern or "([^\r\n]+)\r?\n";
			assert(pcall(string.match, "", pattern), "invalid pattern for <"..url..">");
			if opts.hash then
				assert(opts.hash:match("^%w+$") and type(hashes[opts.hash]) == "function", "invalid hash function: "..opts.hash);
				self.hash_function = hashes[opts.hash];
			end
			local etag;
			local failure_count = 0;
			local retry_intervals = { 60, 120, 300 };
			local function update_list()
				http.request(url, {
					headers = {
						["If-None-Match"] = etag;
					};
				}, function (body, code, response)
					local next_poll = poll_interval;
					if code == 200 and body then
						etag = response.headers.etag;
						local items = {};
						for entry in body:gmatch(pattern) do
							items[entry] = true;
						end
						self.items = items;
						module:log("debug", "Fetched updated list from <%s>", url);
					elseif code == 304 then
						module:log("debug", "List at <%s> is unchanged", url);
					elseif code == 0 or (code >= 400 and code <=599) then
						module:log("warn", "Failed to fetch list from <%s>: %d %s", url, code, tostring(body));
						next_poll = 300;
						failure_count = failure_count + 1;
						next_poll = retry_intervals[failure_count] or retry_intervals[#retry_intervals];
					end
					if next_poll > 0 then
						timer.add_task(next_poll+math.random(0, 60), update_list);
					end
				end);
			end
			update_list();
		end;
		add = function ()
		end;
		remove = function ()
		end;
		contains = function (self, item)
			if self.hash_function then
				item = self.hash_function(item);
			end
			return self.items and self.items[item] == true;
		end;
	};
	file = {
		init = function (self, file_spec, opts)
			local filename = file_spec:gsub("^file:", "");
			local file, err = io.open(filename);
			if not file then
				module:log("warn", "Failed to open list from %s: %s", filename, err);
				return;
			end
			local items = {};
			for line in file:lines() do
				items[line] = true;
			end
			self.items = items;
		end;
		add = function (self, item)
			self.items[item] = true;
		end;
		remove = function (self, item)
			self.items[item] = nil;
		end;
		contains = function (self, item)
			return self.items and self.items[item] == true;
		end;
	};
};
list_backends.https = list_backends.http;

local function create_list(list_backend, list_def, opts)
	if not list_backends[list_backend] then
		error("Unknown list type '"..list_backend.."'", 0);
	end
	local list = setmetatable({}, { __index = list_backends[list_backend] });
	if list.init then
		list:init(list_def, opts);
	end
	return list;
end

--[[
%LIST spammers: memory (source: /etc/spammers.txt)

%LIST spammers: memory (source: /etc/spammers.txt)


%LIST spammers: http://example.com/blacklist.txt
]]

function definition_handlers.LIST(list_name, list_definition)
	local list_backend = list_definition:match("^%w+");
	local opts = {};
	local opt_string = list_definition:match("^%S+%s+%((.+)%)");
	if opt_string then
		for opt_k, opt_v in opt_string:gmatch("(%w+): ?([^,]+)") do
			opts[opt_k] = opt_v;
		end
	end
	return create_list(list_backend, list_definition:match("^%S+"), opts);
end

function definition_handlers.PATTERN(name, pattern)
	local ok, err = pcall(string.match, "", pattern);
	if not ok then
		error("Invalid pattern '"..name.."': "..err);
	end
	return pattern;
end

function definition_handlers.SEARCH(name, pattern)
	return pattern;
end

return definition_handlers;
