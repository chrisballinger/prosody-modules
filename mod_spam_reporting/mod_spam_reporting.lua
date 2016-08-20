local st = require "util.stanza";

module:depends("blocklist");

module:add_feature("urn:xmpp:reporting:0");
module:add_feature("urn:xmpp:reporting:reason:spam:0");
module:add_feature("urn:xmpp:reporting:reason:abuse:0");

module:hook("iq-set/self/urn:xmpp:blocking:block", function (event)
	for item in event.stanza.tags[1]:childtags("item") do
		local report = item:get_child("report", "urn:xmpp:reporting:0");
		local jid = item.attr.jid;
		if report and jid then
			local type = report:get_child("spam") and "spam" or
				report:get_child("abuse") and "abuse" or
				"unknown";
			local reason = report:get_child_text("reason") or "no reason given";
			module:log("warn", "Received report of %s from JID '%s', %s", type, jid, reason);
		end
	end
end, 1);
