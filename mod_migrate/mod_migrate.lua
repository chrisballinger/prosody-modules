-- mod_migrate

local sm = require"core.storagemanager";
local um = require"core.usermanager";
local mm = require"core.modulemanager";

function module.command(arg)
	local host, source_stores, migrate_to, user = unpack(arg);
	if not migrate_to then
		return print("Usage: prosodyctl mod_migrate example.com <source-store>[-<store-type>] <target-driver> [users]*");
	end
	sm.initialize_host(host);
	um.initialize_host(host);
	local module = module:context(host);
	for source_store in source_stores:gmatch("[^,]+") do
		local store_type = source_store:match("%-(%a+)$");
		if store_type then
			source_store = source_store:sub(1, -2-#store_type);
		end
		local storage = module:open_store(source_store, store_type);
		local target = assert(sm.load_driver(host, migrate_to));
		target = assert(target:open(source_store, store_type));

		local function migrate_user(username)
			module:log("info", "Migrating %s data for %s", source_store, username);
			local data, err = storage:get(username);
			assert(data or err==nil, err);
			assert(target:set(username, data));
		end

		if store_type == "archive" then
			function migrate_user(username)
				module:log("info", "Migrating %s archive items for %s", source_store, username);
				local count, errs = 0, 0;
				for id, item, when, with in storage:find(username) do
					local ok, err = target:append(username, id, item, when, with);
					if ok then
						count = count + 1;
					else
						module:log("warn", "Error: %s", err);
						errs = errs + 1;
					end
					if ( count + errs ) % 100 == 0 then
						module:log("info", "%d items migrated, %d errors", count, errs);
					end
				end
				module:log("info", "%d items migrated, %d errors", count, errs);
			end
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
end
