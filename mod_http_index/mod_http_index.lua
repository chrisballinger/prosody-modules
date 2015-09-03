local url = require"socket.url";
local render = require"util.interpolation".new("%b{}", require"util.stanza".xml_escape);

module:depends"http";

-- TODO Move templates into files
local base_template = [[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" value="prosody/{prosody_version} mod_{mod_name}">
<link rel="canonical" href="{canonical}">
<title>{title}</title>
<style>
body{background-color:#eeeeec;margin:1ex 0;padding-bottom:3em;font-family:Arial,Helvetica,sans-serif;}
header,footer{margin:1ex 1em;}
footer{font-size:smaller;color:#babdb6;}
.content{background-color:white;padding:1em;list-style-position:inside;}
nav{font-size:large;margin:1ex 1ex;clear:both;line-height:1.5em;}
nav a{padding: 1ex;text-decoration:none;}
@media screen and (min-width: 460px) {
nav{font-size:x-large;margin:1ex 1em;}
}
a:link,a:visited{color:#2e3436;text-decoration:none;}
a:link:hover,a:visited:hover{color:#3465a4;}
ul{padding:0;}
li{list-style:none;}
hr{visibility:hidden;clear:both;}
br{clear:both;}
li:hover time{opacity:1;}
</style>
</head>
<body>
<header>
<h1>{title}</h1>
</header>
<hr>
<div class="content">
<nav>
<ul>{items#
<li><a href="{item.url}" title="{item.module}">{item.name}</a></li>}
</ul>
</nav>
</div>
<hr>
<footer>
<br>
<div class="powered-by">Prosody {prosody_version?}</div>
</footer>
</body>
</html>
]];

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
