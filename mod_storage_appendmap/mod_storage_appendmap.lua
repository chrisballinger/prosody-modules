local dump = require "util.serialization".serialize;
local load = require "util.envload".envloadfile;
local dm = require "core.storagemanager".olddm;

local driver = {};

local map = {};
local map_mt = { __index = map };
map.remove = {};

function map:get(user, key)
	module:log("debug", "map:get(%s, %s)", tostring(user), tostring(key))
	local filename = dm.getpath(user, module.host, self.store, "map");
	module:log("debug", "File is %s", filename);
	local env = {};
	if _VERSION == "Lua 5.1" then -- HACK
		env._ENV = env; -- HACK
	end -- SO MANY HACKS
	local chunk, err, errno = load(filename, env);
	if not chunk then if errno == 2 then return end return chunk, err; end
	local ok, err = pcall(chunk);
	if not ok then return ok, err; end
	if _VERSION == "Lua 5.1" then -- HACK
		env._ENV = nil; -- HACK
	end -- HACKS EVERYWHERE
	if key == nil then
		return env;
	end
	return env[key];
end

local keywords = {
	["do"] = true; ["and"] = true; ["else"] = true; ["break"] = true;
	["if"] = true; ["end"] = true; ["goto"] = true; ["false"] = true;
	["in"] = true; ["for"] = true; ["then"] = true; ["local"] = true;
	["or"] = true; ["nil"] = true; ["true"] = true; ["until"] = true;
	["elseif"] = true; ["function"] = true; ["not"] = true;
	["repeat"] = true; ["return"] = true; ["while"] = true;

	-- _ENV is not technically a keyword but we need to treat it as such
	["_ENV"] = true;
};

function map:set_keys(user, keyvalues)
	local keys, values = {}, {};
	if _VERSION == "Lua 5.1" then
		assert(keyvalues._ENV == nil, "'_ENV' is a restricted key");
	end
	for key, value in pairs(keyvalues) do
		module:log("debug", "user %s sets %q to %s", user, key, tostring(value))
		if type(key) ~= "string" or not key:find("^[%a_][%w_]*$") or keywords[key] then
			key = "_ENV[" .. dump(key) .. "]";
		end
		table.insert(keys, key);
		if value == self.remove then
			table.insert(values, "nil")
		else
			table.insert(values, dump(value))
		end
	end
	local data = table.concat(keys, ", ") .. " = " .. table.concat(values, ", ") .. ";\n";
	return dm.append_raw(user, module.host, self.store, "map", data);
end

function map:set(user, key, value)
	if _VERSION == "Lua 5.1" then
		assert(key ~= "_ENV", "'_ENV' is a restricted key");
	end
	if key == nil then
		local filename = dm.getpath(user, module.host, self.store, "map");
		os.remove(filename);
		return true;
	end
	if type(key) ~= "string" or not key:find("^[%w_][%w%d_]*$") or key == "_ENV" then
		key = "_ENV[" .. dump(key) .. "]";
	end
	local data = key .. " = " .. dump(value) .. ";\n";
	return dm.append_raw(user, module.host, self.store, "map", data);
end

local keyval = {};
local keyval_mt = { __index = keyval };

function keyval:get(user)
	return map.get(self, user);
end

function keyval:set(user, data)
	map.set(self, user);
	if data then
		for k, v in pairs(data) do
			map.set(self, user, k, v);
		end
	end
	return true;
end

-- TODO some kind of periodic compaction thing?
function map:_compact(user)
	local data = self:get(user);
	return keyval.set(self, user, data);
end

function driver:open(store, typ)
	if typ == "map" then
		return setmetatable({ store = store, }, map_mt);
	elseif typ == nil or typ == "keyval" then
		return setmetatable({ store = store, }, keyval_mt);
	end
	return nil, "unsupported-store";
end

module:provides("storage", driver);

