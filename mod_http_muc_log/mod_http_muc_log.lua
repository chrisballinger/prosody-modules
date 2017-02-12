local mt = require"util.multitable";
local datetime = require"util.datetime";
local jid_split = require"util.jid".split;
local nodeprep = require"util.encodings".stringprep.nodeprep;
local uuid = require"util.uuid".generate;
local it = require"util.iterators";
local gettime = require"socket".gettime;
local url = require"socket.url";
local os_time, os_date = os.time, os.date;
local render = require"util.interpolation".new("%b{}", require"util.stanza".xml_escape);

local archive = module:open_store("muc_log", "archive");

-- Support both old and new MUC code
local mod_muc = module:depends"muc";
local rooms = rawget(mod_muc, "rooms");
local each_room = rawget(mod_muc, "each_room") or function() return it.values(rooms); end;
local new_muc = not rooms;
if new_muc then
	rooms = module:shared"muc/rooms";
end
local get_room_from_jid = rawget(mod_muc, "get_room_from_jid") or
	function (jid)
		return rooms[jid];
	end

local function get_room(name)
	local jid = name .. '@' .. module.host;
	return get_room_from_jid(jid);
end

module:depends"http";

local template;
do
	local template_file = module:get_option_string(module.name .. "_template", module.name .. ".html");
	template_file = assert(module:load_resource(template_file));
	template = template_file:read("*a");
	template_file:close();
end

-- local base_url = module:http_url() .. '/'; -- TODO: Generate links in a smart way
local get_link do
	local link, path = { path = '/' }, { "", "", is_directory = true };
	function get_link(room, date)
		path[1], path[2] = room, date;
		path.is_directory = not date;
		link.path = url.build_path(path);
		return url.build(link);
	end
end

local function public_room(room)
	if type(room) == "string" then
		room = get_room(room);
	end
	return (room
		and not (room.get_hidden or room.is_hidden)(room)
		and not (room.get_members_only or room.is_members_only)(room)
		and room._data.logging == true);
end

local function sort_Y(a,b) return a.year > b.year end
local function sort_m(a,b) return a.n > b.n end

local t_diff = os_time(os_date("*t")) - os_time(os_date("!*t"));
local function time(t)
	return os_time(t) + t_diff;
end

local function find_once(room, query, retval)
	if query then query.limit = 1; else query = { limit = 1 }; end
	local iter, err = archive:find(room, query);
	if not iter then return iter, err; end
	if retval then
		return select(retval, iter());
	end
	return iter();
end

local function years_page(event, path)
	local response = event.response;

	local room = nodeprep(path:match("^(.*)/$"));
	if not room or not public_room(room) then return end

	local date_list = archive.dates and archive:dates(room);
	local dates = mt.new();
	if date_list then
		for _, date in ipairs(date_list) do
			local when = datetime.parse(date.."T00:00:00Z");
			local t = os_date("!*t", when);
			dates:set(t.year, t.month, t.day, when);
		end
	else
		module:log("debug", "Find all dates with messages");
		local next_day;
		repeat
			local when = find_once(room, { start = next_day; }, 3);
			if not when then break; end
			local t = os_date("!*t", when);
			dates:set(t.year, t.month, t.day, when );
			next_day = when + (86400 - (when % 86400));
		until not next_day;
	end

	local years = {};

	for current_year, months_t in pairs(dates.data) do
		local t = { year = current_year, month = 1, day = 1 };
		local months = { };
		local year = { year = current_year, months = months };
		years[#years+1] = year;
		for current_month, days_t in pairs(months_t) do
			t.day = 1;
			t.month = current_month;
			local tmp = os_date("!*t", time(t));
			local days = {};
			local week = { days = days }
			local weeks = { week };
			local month = { year = year.year, month = os_date("!%B", time(t)), n = current_month, weeks = weeks };
			months[#months+1] = month;
			local current_day = 1;
			for _=1, (tmp.wday+5)%7 do
				days[current_day], current_day = {}, current_day+1;
			end
			for i = 1, 31 do
				t.day = i;
				tmp = os_date("!*t", time(t));
				if tmp.month ~= current_month then break end
				if i > 1 and tmp.wday == 2 then
					days = {};
					weeks[#weeks+1] = { days = days };
					current_day = 1;
				end
				days[current_day], current_day = { wday = tmp.wday, day = i, href = days_t[i] and datetime.date(days_t[i]) }, current_day+1;
			end
		end
		table.sort(year, sort_m);
	end
	table.sort(years, sort_Y);

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = get_room(room):get_name();
		jid = get_room(room).jid;
		years = years;
		links = {
			{ href = "../", rel = "up", text = "Back to room list" },
		};
	});
end

local function logs_page(event, path)
	local response = event.response;

	local room, date = path:match("^(.-)/(%d%d%d%d%-%d%d%-%d%d)$");
	room = nodeprep(room);
	if not room then
		return years_page(event, path);
	end
	if not public_room(room) then return end

	local logs, i = {}, 1;
	local iter, err = archive:find(room, {
		["start"] = datetime.parse(date.."T00:00:00Z");
		["end"]   = datetime.parse(date.."T23:59:59Z");
	});
	if not iter then
		module:log("warn", "Could not search archive: %s", err or "no error");
		return 500;
	end

	local first, last;
	local verb, subject, body;
	for key, item, when in iter do
		body = item:get_child_text("body");
		subject = item:get_child_text("subject");
		verb = nil;
		if subject then
			verb, body = "set the topic to", subject;
		elseif body and body:sub(1,4) == "/me " then
			verb, body = body:sub(5), nil;
		elseif item.name == "presence" then
			verb = item.attr.type == "unavailable" and "has left" or "has joined";
		end
		if body or verb then
			logs[i], i = {
				key = key;
				datetime = datetime.datetime(when);
				time = datetime.time(when);
				verb = verb;
				body = body;
				nick = select(3, jid_split(item.attr.from));
				st_name = item.name;
				st_type = item.attr.type;
			}, i + 1;
		end
		first = first or key;
		last = key;
	end
	if i == 1 then return end -- No items

	local next_when, prev_when = "", "";
	local date_list = archive.dates and archive:dates(room);
	if date_list then
		for i = 1, #date_list do
			if date_list[i] == date then
				next_when = date_list[i+1] or "";
				prev_when = date_list[i-1] or "";
				break;
			end
		end
	else

		module:log("debug", "Find next date with messages");
		local next_when = find_once(room, { after = last }, 3);
		if next_when then
			next_when = datetime.date(next_when);
			module:log("debug", "Next message: %s", next_when);
		else
			next_when = "";
		end

		module:log("debug", "Find prev date with messages");
		local prev_when = find_once(room, { before = first, reverse = true }, 3);
		if prev_when then
			prev_when = datetime.date(prev_when);
			module:log("debug", "Previous message: %s", prev_when);
		else
			prev_when = "";
		end
	end

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = ("%s - %s"):format(get_room(room):get_name(), date);
		jid = get_room(room).jid;
		lines = logs;
		links = {
			{ href = "./", rel = "up", text = "Back to calendar" },
			{ href = prev_when, rel = "prev", text = prev_when},
			{ href = next_when, rel = "next", text = next_when},
		};
	});
end

local function list_rooms(event)
	local response = event.response;
	local room_list, i = {}, 1;
	for room in each_room() do
		if public_room(room) then
			room_list[i], i = {
				href = get_link(jid_split(room.jid), nil);
				name = room:get_name();
				description = room:get_description();
			}, i + 1;
		end
	end

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = module:get_option_string("name", "Prosody Chatrooms");
		jid = module.host;
		rooms = room_list;
	});
end

local cache = setmetatable({}, {__mode = 'v'});

local function with_cache(f)
	return function (event, path)
		local request, response = event.request, event.response;
		local ckey = path or "";
		local cached = cache[ckey];

		if cached then
			local etag = cached.etag;
			local if_none_match = request.headers.if_none_match;
			if etag == if_none_match then
				module:log("debug", "Client cache hit");
				return 304;
			end
			module:log("debug", "Server cache hit");
			response.headers.etag = etag;
			response.headers.content_type = "text/html; charset=utf-8";
			return cached[1];
		end

		local start = gettime();
		local rendered = f(event, path);
		module:log("debug", "Rendering took %dms", math.floor( (gettime() - start) * 1000 + 0.5));

		if type(rendered) == "string" then
			local etag = uuid();
			cached = { rendered, etag = etag, date = datetime.date() };
			response.headers.etag = etag;
			cache[ckey] = cached;
		end

		response.headers.content_type = "text/html; charset=utf-8";
		return rendered;
	end
end

-- How is cache invalidation a hard problem? ;)
module:hook("muc-broadcast-message", function (event)
	local room = event.room;
	local room_name = jid_split(room.jid);
	local today = datetime.date();
	cache[get_link(room_name)] = nil;
	cache[get_link(room_name, today)] = nil;
end);

module:provides("http", {
	route = {
		["GET /"] = list_rooms;
		["GET /*"] = with_cache(logs_page);
	};
});

