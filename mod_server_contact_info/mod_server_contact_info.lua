-- This plugin implements http://xmpp.org/extensions/xep-0157.html
local t_insert = table.insert;
local array = require "util.array";
local df_new = require "util.dataforms".new;

-- Source: http://xmpp.org/registrar/formtypes.html#http:--jabber.org-network-serverinfo
local valid_types = {
	abuse = true;
	admin = true;
	feedback = true;
	sales = true;
	security = true;
	support = true;
}

local contact_config = module:get_option("contact_info");
if not contact_config or not next(contact_config) then -- we'll use admins from the config as default
	local admins = module:get_option_inherited_set("admins", {});
	if admins:empty() then
		module:log("error", "No contact_info or admins set in config");
		return -- Nothing to attach, so we'll just skip it.
	end
	module:log("debug", "No contact_info in config, using admins as fallback");
	contact_config = {
		admin = array.collect( admins / function(admin) return "xmpp:" .. admin; end);
	};
end

local form_layout = {
	{ value = "http://jabber.org/network/serverinfo"; type = "hidden"; name = "FORM_TYPE"; };
};
local form_values = {};

for t in pairs(valid_types) do
	local addresses = contact_config[t];
	if addresses then
		t_insert(form_layout, { name = t .. "-addresses", type = "list-multi" });
		local values = {};
		if type(addresses) ~= "table" then
			values[1] = { value = addresses };
		else
			for i, address in ipairs(addresses) do
				values[i] = { value = address };
			end
		end
		form_values[t .. "-addresses"] = values;
	end
end

module:add_extension(df_new(form_layout):form(form_values, "result"));
