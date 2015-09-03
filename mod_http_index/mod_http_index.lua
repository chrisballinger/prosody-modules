local url = require"socket.url";
local render = require"util.interpolation".new("%b{}", require"util.stanza".xml_escape);

module:depends"http";

local base_template;
do
	local template_file = module:get_option_string(module.name .. "_template", module.name .. ".html");
	template_file = assert(module:load_resource(template_file));
	base_template = template_file:read("*a");
	template_file:close();
end

local canonical = module:http_url(nil, "/");

local function relative(base, link)
	base = url.parse(base);
	link = url.parse(link);
	for k,v in pairs(base) do
		if link[k] == v then
			link[k] = nil;
		end
	end
	return url.build(link);
end

local function handler(event)
	local host_items = module:get_host_items("http-provider");
	local http_apps = {}
	for _, item in ipairs(host_items) do
		if module.name ~= item._provided_by then
			table.insert(http_apps, {
				name = item.name;
				module = "mod_" .. item._provided_by;
				url = relative(canonical, module:http_url(item.name, item.default_path));
			});
		end
	end
	event.response.headers.content_type = "text/html";
	return render(base_template, {
		title = "HTTP Apps";
		items = http_apps;
		prosody_version = prosody.version;
		mod_name = module.name;
		canonical = canonical;
	});
end

module:provides("http", {
	route = {
		["GET /"] = handler;
	};
	default_path = "/";
});
