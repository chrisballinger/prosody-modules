--luacheck: globals meta idsafe
local condition_handlers = {};

local jid = require "util.jid";

-- Helper to convert user-input strings (yes/true//no/false) to a bool
local function string_to_boolean(s)
	s = s:lower();
	return s == "yes" or s == "true";
end

-- Return a code string for a condition that checks whether the contents
-- of variable with the name 'name' matches any of the values in the
-- comma/space/pipe delimited list 'values'.
local function compile_comparison_list(name, values)
	local conditions = {};
	for value in values:gmatch("[^%s,|]+") do
		table.insert(conditions, ("%s == %q"):format(name, value));
	end
	return table.concat(conditions, " or ");
end

function condition_handlers.KIND(kind)
	return compile_comparison_list("name", kind), { "name" };
end

local wildcard_equivs = { ["*"] = ".*", ["?"] = "." };

local function compile_jid_match_part(part, match)
	if not match then
		return part.." == nil";
	end
	local pattern = match:match("^<(.*)>$");
	if pattern then
		if pattern == "*" then
			return part;
		end
		if pattern:find("^<.*>$") then
			pattern = pattern:match("^<(.*)>$");
		else
			pattern = pattern:gsub("%p", "%%%0"):gsub("%%(%p)", wildcard_equivs);
		end
		return ("(%s and %s:find(%q))"):format(part, part, "^"..pattern.."$");
	else
		return ("%s == %q"):format(part, match);
	end
end

local function compile_jid_match(which, match_jid)
	local match_node, match_host, match_resource = jid.split(match_jid);
	local conditions = {};
	conditions[#conditions+1] = compile_jid_match_part(which.."_node", match_node);
	conditions[#conditions+1] = compile_jid_match_part(which.."_host", match_host);
	if match_resource then
		conditions[#conditions+1] = compile_jid_match_part(which.."_resource", match_resource);
	end
	return table.concat(conditions, " and ");
end

function condition_handlers.TO(to)
	return compile_jid_match("to", to), { "split_to" };
end

function condition_handlers.FROM(from)
	return compile_jid_match("from", from), { "split_from" };
end

function condition_handlers.FROM_EXACTLY(from)
	return ("from == %q"):format(from), { "from" };
end

function condition_handlers.TO_EXACTLY(to)
	return ("to == %q"):format(to), { "to" };
end

function condition_handlers.TO_SELF()
	return ("to == nil");
end

function condition_handlers.TYPE(type)
	return compile_comparison_list("(type or (name == 'message' and 'normal') or (name == 'presence' and 'available'))", type), { "type", "name" };
end

local function zone_check(zone, which)
	local which_not = which == "from" and "to" or "from";
	return ("(zone_%s[%s_host] or zone_%s[%s] or zone_%s[bare_%s]) "
		.."and not(zone_%s[%s_host] or zone_%s[%s] or zone_%s[bare_%s])"
		)
		:format(zone, which, zone, which, zone, which,
		zone, which_not, zone, which_not, zone, which_not), {
			"split_to", "split_from", "bare_to", "bare_from", "zone:"..zone
		};
end

function condition_handlers.ENTERING(zone)
	return zone_check(zone, "to");
end

function condition_handlers.LEAVING(zone)
	return zone_check(zone, "from");
end

function condition_handlers.IN_ROSTER(yes_no)
	local in_roster_requirement = string_to_boolean(yes_no);
	return "not "..(in_roster_requirement and "not" or "").." roster_entry", { "roster_entry" };
end

function condition_handlers.IN_ROSTER_GROUP(group)
	return ("not not (roster_entry and roster_entry.groups[%q])"):format(group), { "roster_entry" };
end

function condition_handlers.SUBSCRIBED()
	return "rostermanager.is_contact_subscribed(to_node, to_host, bare_from)",
	       { "rostermanager", "split_to", "bare_from" };
end

function condition_handlers.PAYLOAD(payload_ns)
	return ("stanza:get_child(nil, %q)"):format(payload_ns);
end

function condition_handlers.INSPECT(path)
	if path:find("=") then
		local query, match_type, value = path:match("(.-)([~/$]*)=(.*)");
		if not(query:match("#$") or query:match("@[^/]+")) then
			error("Stanza path does not return a string (append # for text content or @name for value of named attribute)", 0);
		end
		local quoted_value = ("%q"):format(value);
		if match_type:find("$", 1, true) then
			match_type = match_type:gsub("%$", "");
			quoted_value = meta(quoted_value);
		end
		if match_type == "~" then -- Lua pattern match
			return ("(stanza:find(%q) or ''):match(%s)"):format(query, quoted_value);
		elseif match_type == "/" then -- find literal substring
			return ("(stanza:find(%q) or ''):find(%s, 1, true)"):format(query, quoted_value);
		elseif match_type == "" then -- exact match
			return ("stanza:find(%q) == %s"):format(query, quoted_value);
		else
			error("Unrecognised comparison '"..match_type.."='", 0);
		end
	end
	return ("stanza:find(%q)"):format(path);
end

function condition_handlers.FROM_GROUP(group_name)
	return ("group_contains(%q, bare_from)"):format(group_name), { "group_contains", "bare_from" };
end

function condition_handlers.TO_GROUP(group_name)
	return ("group_contains(%q, bare_to)"):format(group_name), { "group_contains", "bare_to" };
end

function condition_handlers.FROM_ADMIN_OF(host)
	return ("is_admin(bare_from, %s)"):format(host ~= "*" and host or nil), { "is_admin", "bare_from" };
end

function condition_handlers.TO_ADMIN_OF(host)
	return ("is_admin(bare_to, %s)"):format(host ~= "*" and host or nil), { "is_admin", "bare_to" };
end

local day_numbers = { sun = 0, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 };

local function current_time_check(op, hour, minute)
	hour, minute = tonumber(hour), tonumber(minute);
	local adj_op = op == "<" and "<" or ">="; -- Start time inclusive, end time exclusive
	if minute == 0 then
		return "(current_hour"..adj_op..hour..")";
	else
		return "((current_hour"..op..hour..") or (current_hour == "..hour.." and current_minute"..adj_op..minute.."))";
	end
end

local function resolve_day_number(day_name)
	return assert(day_numbers[day_name:sub(1,3):lower()], "Unknown day name: "..day_name);
end

function condition_handlers.DAY(days)
	local conditions = {};
	for day_range in days:gmatch("[^,]+") do
		local day_start, day_end = day_range:match("(%a+)%s*%-%s*(%a+)");
		if day_start and day_end then
			local day_start_num, day_end_num = resolve_day_number(day_start), resolve_day_number(day_end);
			local op = "and";
			if day_end_num < day_start_num then
				op = "or";
			end
			table.insert(conditions, ("current_day >= %d %s current_day <= %d"):format(day_start_num, op, day_end_num));
		elseif day_range:find("%a") then
			local day = resolve_day_number(day_range:match("%a+"));
			table.insert(conditions, "current_day == "..day);
		else
			error("Unable to parse day/day range: "..day_range);
		end
	end
	assert(#conditions>0, "Expected a list of days or day ranges");
	return "("..table.concat(conditions, ") or (")..")", { "time:day" };
end

function condition_handlers.TIME(ranges)
	local conditions = {};
	for range in ranges:gmatch("([^,]+)") do
		local clause = {};
		range = range:lower()
			:gsub("(%d+):?(%d*) *am", function (h, m) return tostring(tonumber(h)%12)..":"..(tonumber(m) or "00"); end)
			:gsub("(%d+):?(%d*) *pm", function (h, m) return tostring(tonumber(h)%12+12)..":"..(tonumber(m) or "00"); end);
		local start_hour, start_minute = range:match("(%d+):(%d+) *%-");
		local end_hour, end_minute = range:match("%- *(%d+):(%d+)");
		local op = tonumber(start_hour) > tonumber(end_hour) and " or " or " and ";
		if start_hour and end_hour then
			table.insert(clause, current_time_check(">", start_hour, start_minute));
			table.insert(clause, current_time_check("<", end_hour, end_minute));
		end
		if #clause == 0 then
			error("Unable to parse time range: "..range);
		end
		table.insert(conditions, "("..table.concat(clause, " "..op.." ")..")");
	end
	return table.concat(conditions, " or "), { "time:hour,min" };
end

function condition_handlers.LIMIT(spec)
	local name, param = spec:match("^(%w+) on (.+)$");

	if not name then
		name = spec:match("^%w+$");
		if not name then
			error("Unable to parse LIMIT specification");
		end
	else
		param = meta(("%q"):format(param));
	end

	if not param then
		return ("not global_throttle_%s:poll(1)"):format(name), { "globalthrottle:"..name };
	end
	return ("not multi_throttle_%s:poll_on(%s, 1)"):format(name, param), { "multithrottle:"..name };	
end

function condition_handlers.ORIGIN_MARKED(name_and_time)
	local name, time = name_and_time:match("^%s*([%w_]+)%s+%(([^)]+)s%)%s*$");
	if not name then
		name = name_and_time:match("^%s*([%w_]+)%s*$");
	end
	if not name then
		error("Error parsing mark name, see documentation for usage examples");
	end
	if time then
		return ("(current_timestamp - (session.firewall_marked_%s or 0)) < %d"):format(idsafe(name), tonumber(time)), { "timestamp" };
	end
	return ("not not session.firewall_marked_"..idsafe(name));
end

return condition_handlers;
