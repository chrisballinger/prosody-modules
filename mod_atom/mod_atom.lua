-- HTTP Access to PEP -> microblog
-- By Kim Alvefur <zash@zash.se>

module:depends"http";
module:depends"pep";
local nodeprep = require "util.encodings".stringprep.nodeprep;
local st = require "util.stanza";
local host, hosts = module.host, hosts;

local function handle_request(event, path)
	local response = event.response;

	local user = nodeprep(path);
	if not user then return 400 end
	local jid = user .. "@" .. host;

	local pep_data = hosts[host].modules.pep.module.save();
	if not pep_data.data[jid] or
			not pep_data.data[jid]["urn:xmpp:microblog:0"] then
		return 404;
	end

	local microblogdata = pep_data.data[jid]["urn:xmpp:microblog:0"][2]:get_child("entry", "http://www.w3.org/2005/Atom");
	if not microblogdata then return 404; end
	local feed = st.stanza("feed", { xmlns="http://www.w3.org/2005/Atom" } );
	local source = microblogdata:get_child("source");
	if source then
		for i = 1,#source do
			feed:add_child(source[i]):up();
		end
		for i = 1,#microblogdata do
			if microblogdata[i].name == "source" then
				table.remove(microblogdata, i);
				break
			end
		end
	end
	feed:add_child(microblogdata);
	response.headers.content_type = "application/atom+xml";
	return "<?xml version='1.0' encoding='utf-8'?>" .. tostring(feed) .. "\n";
end

module:provides("http", {
	route = {
		["GET /*"] = handle_request;
	};
});
