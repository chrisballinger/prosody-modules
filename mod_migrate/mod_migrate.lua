-- mod_migrate

local sm = require"core.storagemanager";
local um = require"core.usermanager";
local mm = require"core.modulemanager";

function module.command(arg)
	local host, source_store, migrate_to, user = unpack(arg);
	if not migrate_to then
		return print("Usage: prosodyctl mod_migrate example.com <source-store> <target-driver> [users]*");
	end
	sm.initialize_host(host);
	um.initialize_host(host);
	local module = module:context(host);
	local storage = module:open_store(source_store);
	local target = assert(sm.load_driver(host, migrate_to));
	target = assert(target:open(source_store));
	local function migrate_user(username)
		module:log("info", "Migrating data for %s", username);
		local data, err = storage:get(username);
		assert(data or err==nil, err);
		assert(target:set(username, data));
	end

	if arg[4] then
		for i = 4, #arg do
			migrate_user(arg[i]);
		end
	else
		for user in um.users(host) do
			migrate_user(user);
		end
	end
end
