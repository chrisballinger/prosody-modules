-- mod_persisthosts
module:set_global();

local set = require"util.set";
local stat = require"lfs".attributes;
local resolve_relative_path = require"core.configmanager".resolve_relative_path;

local vhost_path = module:get_option_string("persisthosts_path", "conf.d");
local path_pattern = resolve_relative_path(prosody.paths.config, vhost_path) .. "/%s.cfg.lua";

local original = set.new();
original:include(prosody.hosts);

module:hook("host-activated", function(host)
	if not original:contains(host) then
		local path = path_pattern:format(host);
		if not stat(path) then
			local fh, err = io.open(path, "w");
			if fh then
				fh:write(("VirtualHost%q\n"):format(host));
				fh:close();
				module:log("info", "Config file for host '%s' created", host);
			else
				module:log("error", "Could not open '%s' for writing: %s", path, err or "duno");
			end
		else
			module:log("debug", "File '%s' existed already", path);
		end
	else
		module:log("debug", "VirtualHost '%s' existed already", host);
	end
end);

