-- mod_storage_lmdb
-- Copyright (C) 2015 Kim Alvefur
--
-- This file is MIT/X11 licensed.
-- 
-- Depends on lightningdbm
-- https://github.com/shmul/lightningdbm
--
-- luacheck: globals prosody open

local lmdb = require"lightningmdb";
local lfs = require"lfs";
local path = require"util.paths";
local serialization = require"util.serialization";
local serialize = serialization.serialize;
local deserialize = serialization.deserialize;

local base_path = path.resolve_relative_path(prosody.paths.data, module.host);
lfs.mkdir(base_path);

local env = lmdb.env_create();
assert(env:set_maxdbs(module:get_option_number("lmdb_maxdbs", 20)));
local env_flags = 0;
for i, flag in ipairs(module:get_option_array("lmdb_flags", {})) do
	env_flags = env_flags + assert(lmdb["MDB_"..flag:upper()], "No such flag "..flag);
end
env:open(base_path, env_flags, tonumber("640", 8));

local keyval = {};
local keyval_mt = { __index = keyval, flags = lmdb.MDB_CREATE };

function keyval:set(user, value)
	local t = self.env:txn_begin(nil, 0);
	if type(value) == "table" and next(value) == nil then
		value = nil;
	end
	if value ~= nil then
		value = serialize(value);
	end
	local ok, err;
	if value ~= nil then
		ok, err = t:put(self.db, user, value, 0);
	else
		ok, err = t:del(self.db, user, value);
	end
	if not ok then
		t:abort();
		return nil, err;
	end
	return t:commit();
end

function keyval:get(user)
	local t = self.env:txn_begin(nil, 0);
	local data, err = t:get(self.db, user, 0);
	if not data then
		t:abort();
		return nil, err;
	end
	t:commit();
	return deserialize(data);
end

local drivers = {
	keyval = keyval_mt;
}

function open(_, store, typ)
	typ = typ or "keyval";
	local driver_mt = drivers[typ];
	if not driver_mt then
		return nil, "unsupported-store";
	end
	local t = env:txn_begin(nil, 0);
	local db = t:dbi_open(store.."_"..typ, driver_mt.flags);
	assert(t:commit());

	return setmetatable({ env = env, store = store, type = typ, db = db }, driver_mt);
end

function module.unload()
	env:sync(1);
	env:close();
end

module:provides("storage");
