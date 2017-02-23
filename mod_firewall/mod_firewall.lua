
local resolve_relative_path = require "core.configmanager".resolve_relative_path;
local logger = require "util.logger".init;
local it = require "util.iterators";

local definitions = module:shared("definitions");
local active_definitions = {
	ZONE = {
		-- Default zone that includes all local hosts
		["$local"] = setmetatable({}, { __index = prosody.hosts });
	};
};

local default_chains = {
	preroute = {
		type = "event";
		priority = 0.1;
		"pre-message/bare", "pre-message/full", "pre-message/host";
		"pre-presence/bare", "pre-presence/full", "pre-presence/host";
		"pre-iq/bare", "pre-iq/full", "pre-iq/host";
	};
	deliver = {
		type = "event";
		priority = 0.1;
		"message/bare", "message/full", "message/host";
		"presence/bare", "presence/full", "presence/host";
		"iq/bare", "iq/full", "iq/host";
	};
	deliver_remote = {
		type = "event"; "route/remote";
		priority = 0.1;
	};
};

local extra_chains = module:get_option("firewall_extra_chains", {});

local chains = {};
for k,v in pairs(default_chains) do
	chains[k] = v;
end
for k,v in pairs(extra_chains) do
	chains[k] = v;
end

-- Returns the input if it is safe to be used as a variable name, otherwise nil
function idsafe(name)
	return name:match("^%a[%w_]*$");
end

local meta_funcs = {
	bare = function (code)
		return "jid_bare("..code..")", {"jid_bare"};
	end;
	node = function (code)
		return "(jid_split("..code.."))", {"jid_split"};
	end;
	host = function (code)
		return "(select(2, jid_split("..code..")))", {"jid_split"};
	end;
	resource = function (code)
		return "(select(3, jid_split("..code..")))", {"jid_split"};
	end;
};

-- Run quoted (%q) strings through this to allow them to contain code. e.g.: LOG=Received: $(stanza:top_tag())
function meta(s, deps, extra)
	return (s:gsub("$(%b())", function (expr)
			expr = expr:gsub("\\(.)", "%1");
			return [["..tostring(]]..expr..[[).."]];
		end)
		:gsub("$(%b<>)", function (expr)
			expr = expr:sub(2,-2);
			local default = "<undefined>";
			expr = expr:gsub("||(%b\"\")$", function (s)
				default = s:sub(2,-2);
				return "";
			end);
			local func_chain = expr:match("|[%w|]+$");
			if func_chain then
				expr = expr:sub(1, -1-#func_chain);
			end
			local code;
			if expr:match("^@") then
				-- Skip stanza:find() for simple attribute lookup
				local attr_name = expr:sub(2);
				if deps and (attr_name == "to" or attr_name == "from" or attr_name == "type") then
					-- These attributes may be cached in locals
					code = attr_name;
					table.insert(deps, attr_name);
				else
					code = "stanza.attr["..("%q"):format(attr_name).."]";
				end
			elseif expr:match("^%w+#$") then
				code = ("stanza:get_child_text(%q)"):format(expr:sub(1, -2));
			else
				code = ("stanza:find(%q)"):format(expr);
			end
			if func_chain then
				for func_name in func_chain:gmatch("|(%w+)") do
					if code == "to" or code == "from" then
						if func_name == "bare" then
							code = "bare_"..code;
							table.insert(deps, code);
						elseif func_name == "node" or func_name == "host" or func_name == "resource" then
							table.insert(deps, "split_"..code);
							code = code.."_"..func_name;
						end
					else
						assert(meta_funcs[func_name], "unknown function: "..func_name);
						local new_code, new_deps = meta_funcs[func_name](code);
						code = new_code;
						if new_deps and #new_deps > 0 then
							assert(deps, "function not supported here: "..func_name);
							for _, dep in ipairs(new_deps) do
								table.insert(deps, dep);
							end
						end
					end
				end
			end
			return "\"..tostring("..code.." or "..("%q"):format(default)..")..\"";
		end)
		:gsub("$$(%a+)", extra or {})
		:gsub([[^""%.%.]], "")
		:gsub([[%.%.""$]], ""));
end

function metaq(s, ...)
	return meta(("%q"):format(s), ...);
end

local escape_chars = {
	a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
	v = "\v", ["\\"] = "\\", ["\""] = "\"", ["\'"] = "\'"
};
function stripslashes(s)
	return (s:gsub("\\(.)", escape_chars));
end

-- Dependency locations:
-- <type lib>
-- <type global>
-- function handler()
--   <local deps>
--   if <conditions> then
--     <actions>
--   end
-- end

local available_deps = {
	st = { global_code = [[local st = require "util.stanza";]]};
	it = { global_code = [[local it = require "util.iterators";]]};
	it_count = { global_code = [[local it_count = it.count;]], depends = { "it" } };
	current_host = { global_code = [[local current_host = module.host;]] };
	jid_split = {
		global_code = [[local jid_split = require "util.jid".split;]];
	};
	jid_bare = {
		global_code = [[local jid_bare = require "util.jid".bare;]];
	};
	to = { local_code = [[local to = stanza.attr.to or jid_bare(session.full_jid);]]; depends = { "jid_bare" } };
	from = { local_code = [[local from = stanza.attr.from;]] };
	type = { local_code = [[local type = stanza.attr.type;]] };
	name = { local_code = [[local name = stanza.name;]] };
	split_to = { -- The stanza's split to address
		depends = { "jid_split", "to" };
		local_code = [[local to_node, to_host, to_resource = jid_split(to);]];
	};
	split_from = { -- The stanza's split from address
		depends = { "jid_split", "from" };
		local_code = [[local from_node, from_host, from_resource = jid_split(from);]];
	};
	bare_to = { depends = { "jid_bare", "to" }, local_code = "local bare_to = jid_bare(to)"};
	bare_from = { depends = { "jid_bare", "from" }, local_code = "local bare_from = jid_bare(from)"};
	group_contains = {
		global_code = [[local group_contains = module:depends("groups").group_contains]];
	};
	is_admin = { global_code = [[local is_admin = require "core.usermanager".is_admin;]]};
	core_post_stanza = { global_code = [[local core_post_stanza = prosody.core_post_stanza;]] };
	zone = { global_code = function (zone)
		assert(idsafe(zone), "Invalid zone name: "..zone);
		return ("local zone_%s = zones[%q] or {};"):format(zone, zone);
	end };
	date_time = { global_code = [[local os_date = os.date]]; local_code = [[local current_date_time = os_date("*t");]] };
	time = { local_code = function (what)
		local defs = {};
		for field in what:gmatch("%a+") do
			table.insert(defs, ("local current_%s = current_date_time.%s;"):format(field, field));
		end
		return table.concat(defs, " ");
	end, depends = { "date_time" }; };
	timestamp = { global_code = [[local get_time = require "socket".gettime;]]; local_code = [[local current_timestamp = get_time();]]; };
	globalthrottle = {
		global_code = function (throttle)
			assert(idsafe(throttle), "Invalid rate limit name: "..throttle);
			assert(active_definitions.RATE[throttle], "Unknown rate limit: "..throttle);
			return ("local global_throttle_%s = rates.%s:single();"):format(throttle, throttle);
		end;
	};
	multithrottle = {
		global_code = function (throttle)
			assert(pcall(require, "util.cache"), "Using LIMIT with 'on' requires Prosody 0.10 or higher");
			assert(idsafe(throttle), "Invalid rate limit name: "..throttle);
			assert(active_definitions.RATE[throttle], "Unknown rate limit: "..throttle);
			return ("local multi_throttle_%s = rates.%s:multi();"):format(throttle, throttle);
		end;
	};
	rostermanager = {
		global_code = [[local rostermanager = require "core.rostermanager";]];
	};
	roster_entry = {
		local_code = [[local roster_entry = (to_node and rostermanager.load_roster(to_node, to_host) or {})[bare_from];]];
		depends = { "rostermanager", "split_to", "bare_from" };
	};
	list = { global_code = function (list)
			assert(idsafe(list), "Invalid list name: "..list);
			assert(active_definitions.LIST[list], "Unknown list: "..list);
			return ("local list_%s = lists[%q];"):format(list, list);
		end
	};
	search = {
		local_code = function (search_name)
			local search_path = assert(active_definitions.SEARCH[search_name], "Undefined search path: "..search_name);
			return ("local search_%s = tostring(stanza:find(%q) or \"\")"):format(search_name, search_path);
		end;
	};
	pattern = {
		local_code = function (pattern_name)
			local pattern = assert(active_definitions.PATTERN[pattern_name], "Undefined pattern: "..pattern_name);
			return ("local pattern_%s = %q"):format(pattern_name, pattern);
		end;
	};
	tokens = {
		local_code = function (search_and_pattern)
			local search_name, pattern_name = search_and_pattern:match("^([^%-]+)_(.+)$");
			local code = ([[local tokens_%s_%s = {};
			if search_%s then
				for s in search_%s:gmatch(pattern_%s) do
					tokens_%s_%s[s] = true;
				end
			end
			]]):format(search_name, pattern_name, search_name, search_name, pattern_name, search_name, pattern_name);
			return code, { "search:"..search_name, "pattern:"..pattern_name };
		end;
	};
	scan_list = {
		global_code = [[local function scan_list(list, items) for item in pairs(items) do if list:contains(item) then return true; end end end]];
	}
};

local function include_dep(dependency, code)
	local dep, dep_param = dependency:match("^([^:]+):?(.*)$");
	local dep_info = available_deps[dep];
	if not dep_info then
		module:log("error", "Dependency not found: %s", dep);
		return;
	end
	if code.included_deps[dep] ~= nil then
		if code.included_deps[dep] ~= true then
			module:log("error", "Circular dependency on %s", dep);
		end
		return;
	end
	code.included_deps[dep] = false; -- Pending flag (used to detect circular references)
	for _, dep_dep in ipairs(dep_info.depends or {}) do
		include_dep(dep_dep, code);
	end
	if dep_info.global_code then
		if dep_param ~= "" then
			local global_code, deps = dep_info.global_code(dep_param);
			if deps then
				for _, dep in ipairs(deps) do
					include_dep(dep, code);
				end
			end
			table.insert(code.global_header, global_code);
		else
			table.insert(code.global_header, dep_info.global_code);
		end
	end
	if dep_info.local_code then
		if dep_param ~= "" then
			local local_code, deps = dep_info.local_code(dep_param);
			if deps then
				for _, dep in ipairs(deps) do
					include_dep(dep, code);
				end
			end
			table.insert(code, "\n\t\t-- "..dep.."\n\t\t"..local_code.."\n");
		else
			table.insert(code, "\n\t\t-- "..dep.."\n\t\t"..dep_info.local_code.."\n");
		end
	end
	code.included_deps[dep] = true;
end

local definition_handlers = module:require("definitions");
local condition_handlers = module:require("conditions");
local action_handlers = module:require("actions");

local function new_rule(ruleset, chain)
	assert(chain, "no chain specified");
	local rule = { conditions = {}, actions = {}, deps = {} };
	table.insert(ruleset[chain], rule);
	return rule;
end

local function parse_firewall_rules(filename)
	local line_no = 0;

	local function errmsg(err)
		return "Error compiling "..filename.." on line "..line_no..": "..err;
	end

	local ruleset = {
		deliver = {};
	};

	local chain = "deliver"; -- Default chain
	local rule;

	local file, err = io.open(filename);
	if not file then return nil, err; end

	local state; -- nil -> "rules" -> "actions" -> nil -> ...

	local line_hold;
	for line in file:lines() do
		line = line:match("^%s*(.-)%s*$");
		if line_hold and line:sub(-1,-1) ~= "\\" then
			line = line_hold..line;
			line_hold = nil;
		elseif line:sub(-1,-1) == "\\" then
			line_hold = (line_hold or "")..line:sub(1,-2);
		end
		line_no = line_no + 1;

		if line_hold or line:find("^[#;]") then -- luacheck: ignore 542
			-- No action; comment or partial line
		elseif line == "" then
			if state == "rules" then
				return nil, ("Expected an action on line %d for preceding criteria")
					:format(line_no);
			end
			state = nil;
		elseif not(state) and line:sub(1, 2) == "::" then
			chain = line:gsub("^::%s*", "");
			local chain_info = chains[chain];
			if not chain_info then
				if chain:match("^user/") then
					chains[chain] = { type = "event", priority = 1, "firewall/chains/"..chain };
				else
					return nil, errmsg("Unknown chain: "..chain);
				end
			elseif chain_info.type ~= "event" then
				return nil, errmsg("Only event chains supported at the moment");
			end
			ruleset[chain] = ruleset[chain] or {};
		elseif not(state) and line:sub(1,1) == "%" then -- Definition (zone, limit, etc.)
			local what, name = line:match("^%%%s*(%w+) +([^ :]+)");
			if not definition_handlers[what] then
				return nil, errmsg("Definition of unknown object: "..what);
			elseif not name or not idsafe(name) then
				return nil, errmsg("Invalid "..what.." name");
			end

			local val = line:match(": ?(.*)$");
			if not val and line:find(":<") then -- Read from file
				local fn = line:match(":< ?(.-)%s*$");
				if not fn then
					return nil, errmsg("Unable to parse filename");
				end
				local f, err = io.open(fn);
				if not f then return nil, errmsg(err); end
				val = f:read("*a"):gsub("\r?\n", " "):gsub("%s+$", "");
			end
			if not val then
				return nil, errmsg("No value given for definition");
			end

			local ok, ret = pcall(definition_handlers[what], name, val);
			if not ok then
				return nil, errmsg(ret);
			end

			if not active_definitions[what] then
				active_definitions[what] = {};
			end
			active_definitions[what][name] = ret;
		elseif line:find("^[%w_ ]+[%.=]") then
			-- Action
			if state == nil then
				-- This is a standalone action with no conditions
				rule = new_rule(ruleset, chain);
			end
			state = "actions";
			-- Action handlers?
			local action = line:match("^[%w_ ]+"):upper():gsub(" ", "_");
			if not action_handlers[action] then
				return nil, ("Unknown action on line %d: %s"):format(line_no, action or "<unknown>");
			end
			table.insert(rule.actions, "-- "..line)
			local ok, action_string, action_deps = pcall(action_handlers[action], line:match("=(.+)$"));
			if not ok then
				return nil, errmsg(action_string);
			end
			table.insert(rule.actions, action_string);
			for _, dep in ipairs(action_deps or {}) do
				table.insert(rule.deps, dep);
			end
		elseif state == "actions" then -- state is actions but action pattern did not match
			state = nil; -- Awaiting next rule, etc.
			table.insert(ruleset[chain], rule);
			rule = nil;
		else
			if not state then
				state = "rules";
				rule = new_rule(ruleset, chain);
			end
			-- Check standard modifiers for the condition (e.g. NOT)
			local negated;
			local condition = line:match("^[^:=%.?]*");
			if condition:find("%f[%w]NOT%f[^%w]") then
				local s, e = condition:match("%f[%w]()NOT()%f[^%w]");
				condition = (condition:sub(1,s-1)..condition:sub(e+1, -1)):match("^%s*(.-)%s*$");
				negated = true;
			end
			condition = condition:gsub(" ", "_");
			if not condition_handlers[condition] then
				return nil, ("Unknown condition on line %d: %s"):format(line_no, (condition:gsub("_", " ")));
			end
			-- Get the code for this condition
			local ok, condition_code, condition_deps = pcall(condition_handlers[condition], line:match(":%s?(.+)$"));
			if not ok then
				return nil, errmsg(condition_code);
			end
			if negated then condition_code = "not("..condition_code..")"; end
			table.insert(rule.conditions, condition_code);
			for _, dep in ipairs(condition_deps or {}) do
				table.insert(rule.deps, dep);
			end
		end
	end
	return ruleset;
end

local function process_firewall_rules(ruleset)
	-- Compile ruleset and return complete code

	local chain_handlers = {};

	-- Loop through the chains in the parsed ruleset (e.g. incoming, outgoing)
	for chain_name, rules in pairs(ruleset) do
		local code = { included_deps = {}, global_header = {} };
		local condition_uses = {};
		-- This inner loop assumes chain is an event-based, not a filter-based
		-- chain (filter-based will be added later)
		for _, rule in ipairs(rules) do
			for _, condition in ipairs(rule.conditions) do
				if condition:find("^not%(.+%)$") then
					condition = condition:match("^not%((.+)%)$");
				end
				condition_uses[condition] = (condition_uses[condition] or 0) + 1;
			end
		end

		local condition_cache, n_conditions = {}, 0;
		for _, rule in ipairs(rules) do
			for _, dep in ipairs(rule.deps) do
				include_dep(dep, code);
			end
			table.insert(code, "\n\t\t");
			local rule_code;
			if #rule.conditions > 0 then
				for i, condition in ipairs(rule.conditions) do
					local negated = condition:match("^not%(.+%)$");
					if negated then
						condition = condition:match("^not%((.+)%)$");
					end
					if condition_uses[condition] > 1 then
						local name = condition_cache[condition];
						if not name then
							n_conditions = n_conditions + 1;
							name = "condition"..n_conditions;
							condition_cache[condition] = name;
							table.insert(code, "local "..name.." = "..condition..";\n\t\t");
						end
						rule.conditions[i] = (negated and "not(" or "")..name..(negated and ")" or "");
					else
						rule.conditions[i] = (negated and "not(" or "(")..condition..")";
					end
				end

				rule_code = "if "..table.concat(rule.conditions, " and ").." then\n\t\t\t"
					..table.concat(rule.actions, "\n\t\t\t")
					.."\n\t\tend\n";
			else
				rule_code = table.concat(rule.actions, "\n\t\t");
			end
			table.insert(code, rule_code);
		end

		for name in pairs(definition_handlers) do
			table.insert(code.global_header, 1, "local "..name:lower().."s = definitions."..name..";");
		end

		local code_string = "return function (definitions, fire_event, log, module)\n\t"
			..table.concat(code.global_header, "\n\t")
			.."\n\tlocal db = require 'util.debug';\n\n\t"
			.."return function (event)\n\t\t"
			.."local stanza, session = event.stanza, event.origin;\n"
			..table.concat(code, "")
			.."\n\tend;\nend";

		chain_handlers[chain_name] = code_string;
	end

	return chain_handlers;
end

local function compile_firewall_rules(filename)
	local ruleset, err = parse_firewall_rules(filename);
	if not ruleset then return nil, err; end
	local chain_handlers = process_firewall_rules(ruleset);
	return chain_handlers;
end

local function compile_handler(code_string, filename)
	-- Prepare event handler function
	local chunk, err = loadstring(code_string, "="..filename);
	if not chunk then
		return nil, "Error compiling (probably a compiler bug, please report): "..err;
	end
	local function fire_event(name, data)
		return module:fire_event(name, data);
	end
	chunk = chunk()(active_definitions, fire_event, logger(filename), module); -- Returns event handler with 'zones' upvalue.
	return chunk;
end

local function resolve_script_path(script_path)
	local relative_to = prosody.paths.config;
	if script_path:match("^module:") then
		relative_to = module.path:sub(1, -#("/mod_"..module.name..".lua"));
		script_path = script_path:match("^module:(.+)$");
	end
	return resolve_relative_path(relative_to, script_path);
end

function module.load()
	if not prosody.arg then return end -- Don't run in prosodyctl
	active_definitions = {};
	local firewall_scripts = module:get_option_set("firewall_scripts", {});
	for script in firewall_scripts do
		script = resolve_script_path(script);
		local chain_functions, err = compile_firewall_rules(script)

		if not chain_functions then
			module:log("error", "Error compiling %s: %s", script, err or "unknown error");
		else
			for chain, handler_code in pairs(chain_functions) do
				local handler, err = compile_handler(handler_code, "mod_firewall::"..chain);
				if not handler then
					module:log("error", "Compilation error for %s: %s", script, err);
				else
					local chain_definition = chains[chain];
					if chain_definition and chain_definition.type == "event" then
						for _, event_name in ipairs(chain_definition) do
							module:hook(event_name, handler, chain_definition.priority);
						end
					elseif not chain:sub(1, 5) == "user/" then
						module:log("warn", "Unknown chain %q", chain);
					end
					module:hook("firewall/chains/"..chain, handler);
				end
			end
		end
	end
	-- Replace contents of definitions table (shared) with active definitions
	for k in it.keys(definitions) do definitions[k] = nil; end
	for k,v in pairs(active_definitions) do definitions[k] = v; end
end

function module.command(arg)
	if not arg[1] or arg[1] == "--help" then
		require"util.prosodyctl".show_usage([[mod_firewall <firewall.pfw>]], [[Compile files with firewall rules to Lua code]]);
		return 1;
	end
	local verbose = arg[1] == "-v";
	if verbose then table.remove(arg, 1); end

	local serialize = require "util.serialization".serialize;
	if verbose then
		print("local logger = require \"util.logger\".init;");
		print();
		print("local function fire_event(name, data)\n\tmodule:fire_event(name, data)\nend");
		print();
	end

	for _, filename in ipairs(arg) do
		filename = resolve_script_path(filename);
		print("do -- File "..filename);
		local chain_functions = assert(compile_firewall_rules(filename));
		if verbose then
			print();
			print("local active_definitions = "..serialize(active_definitions)..";");
			print();
		end
		local c = 0;
		for chain, handler_code in pairs(chain_functions) do
			c = c + 1;
			print("---- Chain "..chain:gsub("_", " "));
			local chain_func_name = "chain_"..tostring(c).."_"..chain:gsub("%p", "_");
			if not verbose then
				print(("%s = %s;"):format(chain_func_name, handler_code:sub(8)));
			else

				print(("local %s = (%s)(active_definitions, fire_event, logger(%q));"):format(chain_func_name, handler_code:sub(8), filename));
				print();

				local chain_definition = chains[chain];
				if chain_definition and chain_definition.type == "event" then
					for _, event_name in ipairs(chain_definition) do
						print(("module:hook(%q, %s, %d);"):format(event_name, chain_func_name, chain_definition.priority or 0));
					end
				end
				print(("module:hook(%q, %s, %d);"):format("firewall/chains/"..chain, chain_func_name, chain_definition.priority or 0));
			end

			print("---- End of chain "..chain);
			print();
		end
		print("end -- End of file "..filename);
	end
end
