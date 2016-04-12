--luacheck: globals meta idsafe
local action_handlers = {};


-- Takes an XML string and returns a code string that builds that stanza
-- using st.stanza()
local function compile_xml(data)
	local code = {};
	local first, short_close = true, nil;
	for tagline, text in data:gmatch("<([^>]+)>([^<]*)") do
		if tagline:sub(-1,-1) == "/" then
			tagline = tagline:sub(1, -2);
			short_close = true;
		end
		if tagline:sub(1,1) == "/" then
			code[#code+1] = (":up()");
		else
			local name, attr = tagline:match("^(%S*)%s*(.*)$");
			local attr_str = {};
			for k, _, v in attr:gmatch("(%S+)=([\"'])([^%2]-)%2") do
				if #attr_str == 0 then
					table.insert(attr_str, ", { ");
				else
					table.insert(attr_str, ", ");
				end
				if k:find("^%a%w*$") then
					table.insert(attr_str, string.format("%s = %q", k, v));
				else
					table.insert(attr_str, string.format("[%q] = %q", k, v));
				end
			end
			if #attr_str > 0 then
				table.insert(attr_str, " }");
			end
			if first then
				code[#code+1] = (string.format("st.stanza(%q %s)", name, #attr_str>0 and table.concat(attr_str) or ", nil"));
				first = nil;
			else
				code[#code+1] = (string.format(":tag(%q%s)", name, table.concat(attr_str)));
			end
		end
		if text and text:find("%S") then
			code[#code+1] = (string.format(":text(%q)", text));
		elseif short_close then
			short_close = nil;
			code[#code+1] = (":up()");
		end
	end
	return table.concat(code, "");
end

function action_handlers.PASS()
	return "do return end"
end

function action_handlers.DROP()
	return "do return true end";
end

function action_handlers.STRIP(tag_desc)
	local code = {};
	local name, xmlns = tag_desc:match("^(%S+) (.+)$");
	if not name then
		name, xmlns = tag_desc, nil;
	end
	if name == "*" then
		name = nil;
	end
	code[#code+1] = ("local stanza_xmlns = stanza.attr.xmlns; ");
	code[#code+1] = "stanza:maptags(function (tag) if ";
	if name then
		code[#code+1] = ("tag.name == %q and "):format(name);
	end
	if xmlns then
		code[#code+1] = ("(tag.attr.xmlns or stanza_xmlns) == %q "):format(xmlns);
	else
		code[#code+1] = ("tag.attr.xmlns == stanza_xmlns ");
	end
	code[#code+1] = "then return nil; end return tag; end );";
	return table.concat(code);
end

function action_handlers.INJECT(tag)
	return "stanza:add_child("..compile_xml(tag)..")", { "st" };
end

local error_types = {
	["bad-request"] = "modify";
	["conflict"] = "cancel";
	["feature-not-implemented"] = "cancel";
	["forbidden"] = "auth";
	["gone"] = "cancel";
	["internal-server-error"] = "cancel";
	["item-not-found"] = "cancel";
	["jid-malformed"] = "modify";
	["not-acceptable"] = "modify";
	["not-allowed"] = "cancel";
	["not-authorized"] = "auth";
	["payment-required"] = "auth";
	["policy-violation"] = "modify";
	["recipient-unavailable"] = "wait";
	["redirect"] = "modify";
	["registration-required"] = "auth";
	["remote-server-not-found"] = "cancel";
	["remote-server-timeout"] = "wait";
	["resource-constraint"] = "wait";
	["service-unavailable"] = "cancel";
	["subscription-required"] = "auth";
	["undefined-condition"] = "cancel";
	["unexpected-request"] = "wait";
};


local function route_modify(make_new, to, drop)
	local reroute, deps = "session.send(newstanza)", { "st" };
	if to then
		reroute = ("newstanza.attr.to = %q; core_post_stanza(session, newstanza)"):format(to);
		deps[#deps+1] = "core_post_stanza";
	end
	return ([[local newstanza = st.%s; %s;%s]])
		:format(make_new, reroute, drop and " return true;" or ""), deps;
end

function action_handlers.BOUNCE(with)
	local error = with and with:match("^%S+") or "service-unavailable";
	local error_type = error:match(":(%S+)");
	if not error_type then
		error_type = error_types[error] or "cancel";
	else
		error = error:match("^[^:]+");
	end
	error, error_type = string.format("%q", error), string.format("%q", error_type);
	local text = with and with:match(" %((.+)%)$");
	if text then
		text = string.format("%q", text);
	else
		text = "nil";
	end
	local route_modify_code, deps = route_modify(("error_reply(stanza, %s, %s, %s)"):format(error_type, error, text), nil, true);
	deps[#deps+1] = "type";
	deps[#deps+1] = "name";
	return [[if type == "error" or (name == "iq" and type == "result") then return true; end -- Don't reply to 'error' stanzas, or iq results
			]]..route_modify_code, deps;
end

function action_handlers.REDIRECT(where)
	return route_modify("clone(stanza)", where, true);
end

function action_handlers.COPY(where)
	return route_modify("clone(stanza)", where, false);
end

function action_handlers.REPLY(with)
	return route_modify(("reply(stanza):body(%q)"):format(with));
end

function action_handlers.LOG(string)
	local level = string:match("^%[(%a+)%]") or "info";
	string = string:gsub("^%[%a+%] ?", "");
	return meta(("(session.log or log)(%q, %q)"):format(level, string));
end

function action_handlers.RULEDEP(dep)
	return "", { dep };
end

function action_handlers.EVENT(name)
	return ("fire_event(%q, event)"):format(name);
end

function action_handlers.JUMP_EVENT(name)
	return ("do return fire_event(%q, event); end"):format(name);
end

function action_handlers.JUMP_CHAIN(name)
	return ("if fire_event(%q, event) then return true; end"):format("firewall/chains/"..name);
end

function action_handlers.MARK_ORIGIN(name)
	return [[session.firewall_marked_]]..idsafe(name)..[[ = current_timestamp;]], { "timestamp" };
end

function action_handlers.UNMARK_ORIGIN(name)
	return [[session.firewall_marked_]]..idsafe(name)..[[ = nil;]]
end

return action_handlers;
