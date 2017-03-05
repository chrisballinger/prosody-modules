-- mod_storage_xmlarchive
-- Copyright (C) 2015-2016 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
-- luacheck: ignore unused self

local lfs = require "lfs";
local dm = require "core.storagemanager".olddm;
local hmac_sha256 = require"util.hashes".hmac_sha256;
local st = require"util.stanza";
local dt = require"util.datetime";
local new_stream = require "util.xmppstream".new;
local empty = {};

if not dm.append_raw then
	module:require"datamanager_append_raw";
end

local archive = {};
local archive_mt = { __index = archive };

local is_stanza = st.is_stanza or function (s)
	return getmetatable(s) == st.stanza_mt;
end

function archive:append(username, _, data, when, with)
	if type(when) ~= "number" then
		when, with, data = data, when, with;
	end
	if not is_stanza(data) then
		module:log("error", "Attempt to store non-stanza object, traceback: %s", debug.traceback());
		return nil, "unsupported-datatype";
	end

	username = username or "@";
	data = tostring(data) .. "\n";

	local day = dt.date(when);
	local ok, err = dm.append_raw(username.."@"..day, module.host, self.store, "xml", data);
	if not ok then
		return nil, err;
	end

	-- If the day-file is missing then we need to add it to the list of days
	local first_of_day = not lfs.attributes(dm.getpath(username .. "@" .. day, module.host, self.store, "list"));

	local offset = ok and err or 0;

	local id = day .. "-" .. hmac_sha256(username.."@"..day.."+"..offset, data, true):sub(-16);
	ok, err = dm.list_append(username.."@"..day, module.host, self.store,
		{ id = id, when = dt.datetime(when), with = with, offset = offset, length = #data });
	if ok and first_of_day then
		ok, err = dm.list_append(username, module.host, self.store, day);
	end
	if not ok then
		return nil, err;
	end
	return id;
end

function archive:_get_idx(username, id, dates)
	dates = dates or self:dates(username) or empty;
	local date = id:sub(1, 10);
	for d = 1, #dates do
		if date == dates[d] then
			module:log("debug", "Loading items from %s", dates[d]);
			local items = dm.list_load(username .. "@" .. dates[d], module.host, self.store) or empty;
			for i = 1, #items do
				if items[i].id == id then
					return d, i, items;
				end
			end
			return; -- Assuming no duplicates
		elseif date < dates[d] then
			return; -- List is assumed to be sorted
		end
	end
end

function archive:find(username, query)
	username = username or "@";
	query = query or empty;

	local result;
	local function cb(_, stanza)
		assert(not result, "Multiple items in chunk");
		result = stanza;
	end

	local stream_sess = { notopen = true };
	local stream = new_stream(stream_sess, { handlestanza = cb, stream_ns = "jabber:client", default_ns = "jabber:client" });
	local dates = dm.list_load(username, module.host, self.store) or empty;
	local function reset_stream()
		stream:reset();
		stream_sess.notopen = true;
		stream:feed(st.stanza("stream", { xmlns = "jabber:client" }):top_tag());
		stream_sess.notopen = nil;
	end
	reset_stream();

	local limit = query.limit;
	local start_day, step, last_day = 1, 1, #dates;
	local count = 0;
	local rev = query.reverse;
	if query.start then
		local d = dt.date(query.start);
		for i = 1, #dates do
			if dates[i] == d then
				start_day = i; break;
			end
		end
	end
	if query["end"] then
		local d = dt.date(query["end"]);
		for i = #dates, 1, -1 do
			if dates[i] == d then
				last_day = i; break;
			end
		end
	end
	local items, xmlfile;
	local first_item, last_item;
	if rev then
		start_day, step, last_day = last_day, -step, start_day;
		if query.before then
			local before_day, before_item, items_ = self:_get_idx(username, query.before, dates);
			if before_day and before_day <= start_day then
				if before_item then
					first_item = before_item - 1;
				else
					first_item = #items_;
				end
				last_item = 1;
				start_day = before_day;
				items = items_;
			end
		end
	elseif query.after then
		local after_day, after_item, items_ = self:_get_idx(username, query.after, dates);
		if after_day and after_day >= start_day then
			if after_item then
				first_item = after_item + 1;
			else
				first_item = 1;
			end
			last_item = #items_;
			start_day = after_day;
			items = items_;
		end
	end

	return function ()
		if limit and count >= limit then if xmlfile then xmlfile:close() end return; end
		local filename;

		for d = start_day, last_day, step do
			if not items then
				module:log("debug", "Loading items from %s", dates[d]);
				start_day = d;
				items = dm.list_load(username .. "@" .. dates[d], module.host, self.store) or empty;
				if not rev then
					first_item, last_item = 1, #items;
				else
					first_item, last_item = #items, 1;
				end
			end

			local q_with, q_start, q_end = query.with, query.start, query["end"];
			for i = first_item, last_item, step do
				local item = items[i];
				if not item then
					module:log("warn", "data[%q][%d] is nil", dates[d], i);
					break;
				end
				local i_when, i_with = item.when, item.with;
				if type(i_when) == "string" then
					i_when = dt.parse(i_when);
				end
				if type(i_when) ~= "number" then
					module:log("warn", "data[%q][%d].when is invalid", dates[d], i);
					break;
				end
				if not xmlfile then
					local ferr;
					filename = dm.getpath(username .. "@" .. dates[d], module.host, self.store, "xml");
					xmlfile, ferr = io.open(filename);
					if not xmlfile then
						module:log("error", "Error: %s", ferr);
						return;
					end
				end
				if  (not q_with or i_with == q_with)
				and (not q_start or i_when >= q_start)
				and (not q_end or i_when <= q_end) then
					count = count + 1;
					first_item = i + step;

					xmlfile:seek("set", item.offset);
					local data = xmlfile:read(item.length);
					local ok, err = stream:feed(data);
					if not ok then
						module:log("warn", "Parse error in %s at %d+%d: %s", filename, item.offset, item.length, err);
						reset_stream();
					end
					if result then
						local stanza = result;
						result = nil;
						return item.id, stanza, i_when, i_with;
					end
				end
			end
			items = nil;
			if xmlfile then
				xmlfile:close();
				xmlfile = nil;
			end
		end
	end
end

function archive:delete(username, query)
	username = username or "@";
	query = query or empty;
	if query.with or query.start or query.after then
		return nil, "not-implemented"; -- Only trimming the oldest messages
	end
	local before = query.before or query["end"] or "9999-12-31";
	if type(before) == "number" then before = dt.date(before); else before = before:sub(1, 10); end
	local dates, err = dm.list_load(username, module.host, self.store);
	if not dates or next(dates) == nil then
		if not err then return true end -- already empty
		return dates, err;
	end
	if dates[1] > before then return true; end -- Nothing to delete
	local remaining_dates = {};
	for d = 1, #dates do
		if dates[d] >= before then
			table.insert(remaining_dates, dates[d]);
		end
	end
	table.sort(remaining_dates);
	local ok, err = dm.list_store(username, module.host, self.store, remaining_dates);
	if not ok then return ok, err; end
	for d = 1, #dates do
		if dates[d] < before then
			os.remove(dm.getpath(username .. "@" .. dates[d], module.host, self.store, "list"));
			os.remove(dm.getpath(username .. "@" .. dates[d], module.host, self.store, "xml"));
		end
	end
	return true;
end

function archive:dates(username)
	return dm.list_load(username, module.host, self.store);
end

local provider = {};
function provider:open(store, typ)
	if typ ~= "archive" then return nil, "unsupported-store"; end
	return setmetatable({ store = store }, archive_mt);
end

function provider:purge(username)
	for store in dm.stores(username, module.host) do
		local dates = dm.list_load(username, module.host, store) or empty;
		if dates[1] and type(dates[1]) == "string" and dates[1]:match("^%d%d%d%d%-%d%d%-%d%d$") then
			module:log("info", "Store %s looks like an archive store, emptying it...", store);
			provider:open(store, "archive"):delete(username);
		end
	end
	return true;
end

module:provides("storage", provider);
