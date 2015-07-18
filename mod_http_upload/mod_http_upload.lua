-- mod_http_upload
--
-- Copyright (C) 2015 Kim Alvefur
--
-- This file is MIT/X11 licensed.
-- 
-- Implementation of HTTP Upload file transfer mechanism used by Conversations
--

-- imports
local st = require"util.stanza";
local lfs = require"lfs";
local join_path = require"util.paths".join;
local uuid = require"util.uuid".generate;

-- depends
module:depends("http");

-- namespace
local xmlns_http_upload = "eu:siacs:conversations:http:upload";

module:add_feature(xmlns_http_upload);

-- state
local pending_slots = module:shared("upload_slots");

local storage_path = join_path(prosody.paths.data, module.name);
lfs.mkdir(storage_path);

-- hooks
module:hook("iq/host/"..xmlns_http_upload..":request", function (event)
	local stanza, origin = event.stanza, event.origin;
	-- local clients only
	if origin.type ~= "c2s" then
		origin.send(st.error_reply(stanza, "cancel", "not-authorized"));
		return true;
	end
	-- validate
	local filename = stanza.tags[1]:get_child_text("filename");
	if not filename or filename:find("/") then
		origin.send(st.error_reply(stanza, "modify", "bad-request"));
		return true;
	end
	local reply = st.reply(stanza);
	reply:tag("slot", { xmlns = xmlns_http_upload });
	local random = uuid();
	pending_slots[random.."/"..filename] = origin.full_jid;
	local url = module:http_url() .. "/" .. random .. "/" .. filename;
	reply:tag("get"):text(url):up();
	reply:tag("put"):text(url):up();
	origin.send(reply);
	return true;
end);

-- http service
local function upload_data(event, path)
	if not pending_slots[path] then
		return 401;
	end
	local random, filename = path:match("^([^/]+)/([^/]+)$");
	if not random then
		return 400;
	end
	local dirname = join_path(storage_path, random);
	if not lfs.mkdir(dirname) then
		module:log("error", "Could not create directory %s for upload", dirname);
		return 500;
	end
	local full_filename = join_path(dirname, filename);
	local fh, ferr = io.open(full_filename, "w");
	if not fh then
		module:log("error", "Could not open file %s for upload: %s", full_filename, ferr);
		return 500;
	end
	local ok, err = fh:write(event.request.body);
	if not ok then
		module:log("error", "Could not write to file %s for upload: %s", full_filename, err);
		os.remove(full_filename);
		return 500;
	end
	ok, err = fh:close();
	if not ok then
		module:log("error", "Could not write to file %s for upload: %s", full_filename, err);
		os.remove(full_filename);
		return 500;
	end
	module:log("info", "File uploaded by %s to slot %s", pending_slots[path], random);
	pending_slots[path] = nil;
	return 200;
end

local serve_uploaded_files = module:depends("http_files").serve(storage_path);

local function size_only(request, data)
	request.headers.content_size = #data;
	return 200;
end

local function serve_head(event, path)
	event.send = size_only;
	return serve_uploaded_files(event, path);
end

module:provides("http", {
	route = {
		["GET /*"] = serve_uploaded_files;
		["HEAD /*"] = serve_head;
		["PUT /*"] = upload_data;
	};
});
