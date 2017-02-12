-- mod_s2s_auth_dane
-- Copyright (C) 2013-2014 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
-- Implements DANE and Secure Delegation using DNS SRV as described in
-- http://tools.ietf.org/html/draft-miller-xmpp-dnssec-prooftype
--
-- Known issues:
-- Could be done much cleaner if mod_s2s was using util.async
--
-- TODO Things to test/handle:
-- Negative or bogus answers
-- No encryption offered
-- Different hostname before and after STARTTLS - mod_s2s should complain
-- Interaction with Dialback
--
-- luacheck: ignore module

module:set_global();

local have_async, async = pcall(require, "util.async");
local noop = function () end
local type = type;
local t_insert = table.insert;
local set = require"util.set";
local dns_lookup = require"net.adns".lookup;
local hashes = require"util.hashes";
local base64 = require"util.encodings".base64;
local idna_to_ascii = require "util.encodings".idna.to_ascii;
local idna_to_unicode = require"util.encodings".idna.to_unicode;
local nameprep = require"util.encodings".stringprep.nameprep;
local cert_verify_identity = require "util.x509".verify_identity;

do
	local net_dns = require"net.dns";
	if not net_dns.types or not net_dns.types[52] then
		module:log("error", "No TLSA support available, DANE will not be supported");
		return
	end
end

local pat = "%-%-%-%-%-BEGIN ([A-Z ]+)%-%-%-%-%-\r?\n"..
"([0-9A-Za-z=+/\r\n]*)\r?\n%-%-%-%-%-END %1%-%-%-%-%-";
local function pem2der(pem)
	local typ, data = pem:match(pat);
	if typ and data then
		return base64.decode(data), typ;
	end
end
local use_map = { ["DANE-EE"] = 3; ["DANE-TA"] = 2; ["PKIX-EE"] = 1; ["PKIX-CA"] = 0 }

local implemented_uses = set.new { "DANE-EE", "PKIX-EE" };
do
	local cert_mt = debug.getregistry()["SSL:Certificate"];
	if cert_mt and cert_mt.__index.issued then
		-- Need cert:issued() for these
		implemented_uses:add("DANE-TA");
		implemented_uses:add("PKIX-CA");
	else
		module:log("debug", "The cert:issued() method is unavailable, DANE-TA and PKIX-CA can't be enabled");
	end
	if not cert_mt.__index.pubkey then
		module:log("debug", "The cert:pubkey() method is unavailable, the SPKI usage can't be supported");
	end
end
local configured_uses = module:get_option_set("dane_uses", { "DANE-EE", "DANE-TA" });
local enabled_uses = set.intersection(implemented_uses, configured_uses) / function(use) return use_map[use] end;
local unsupported = configured_uses - implemented_uses;
if not unsupported:empty() then
	module:log("warn", "Unable to support DANE uses %s", tostring(unsupported));
end

-- Find applicable TLSA records
-- Takes a s2sin/out and a callback
local function dane_lookup(host_session, cb)
	cb = cb or noop;
	local log = host_session.log or module._log;
	if host_session.dane ~= nil then return end -- Has already done a lookup

	if host_session.direction == "incoming" then
		if not host_session.from_host then
			log("debug", "Session doesn't have a 'from' host set");
			return;
		end
		-- We don't know what hostname or port to use for Incoming connections
		-- so we do a SRV lookup and then request TLSA records for each SRV
		-- Most servers will probably use the same certificate on outgoing
		-- and incoming connections, so this should work well
		local name = host_session.from_host and idna_to_ascii(host_session.from_host);
		if not name then
			log("warn", "Could not convert '%s' to ASCII for DNS lookup", tostring(host_session.from_host));
			return;
		end
		log("debug", "Querying SRV records from _xmpp-server._tcp.%s.", name);
		host_session.dane = dns_lookup(function (answer, err)
			host_session.dane = false; -- Mark that we already did the lookup

			if not answer then
				log("debug", "Resolver error: %s", tostring(err));
				return cb(host_session);
			end

			if answer.bogus then
				log("warn", "Results are bogus!");
				-- Bad sign, probably not a good idea to do any fallback here
				host_session.dane = answer;
			elseif not answer.secure then
				log("debug", "Results are not secure");
				return cb(host_session);
			end

			local n = answer.n or #answer;
			if n == 0 then
				-- No SRV records, synthesize fallback host and port
				-- this may behave oddly for connections in the other direction if
				-- mod_s2s doesn't keep the answer around
				answer[1] = { srv = { target = name, port = 5269 } };
				n = 1;
			elseif n == 1 and answer[1].srv.target == '.' then
				return cb(host_session); -- No service ... This shouldn't happen?
			end
			local srv_hosts = { answer = answer };
			host_session.srv_hosts = srv_hosts;
			local dane;
			for _, record in ipairs(answer) do
				t_insert(srv_hosts, record.srv);
				log("debug", "Querying TLSA record for %s:%d", record.srv.target, record.srv.port);
				dns_lookup(function(dane_answer)
					log("debug", "Got answer for %s:%d", record.srv.target, record.srv.port);
					n = n - 1;
					-- There are three kinds of answers
					-- Insecure, Secure and Bogus
					--
					-- We collect Secure answers for later use
					--
					-- Insecure (legacy) answers are simply ignored
					--
					-- If we get a Bogus (dnssec error) reply, keep the
					-- status around.  If there were only bogus replies, the
					-- connection will be aborted.  If there were at least
					-- one non-Bogus reply, we proceed.  If none of the
					-- replies matched, we consider the connection insecure.

					if (dane_answer.bogus or dane_answer.secure) and not dane then
						-- The first answer we care about
						-- For services with only one SRV record, this will be the only one
						log("debug", "First secure (or bogus) TLSA")
						dane = dane_answer;
					elseif dane_answer.bogus then
						log("debug", "Got additional bogus TLSA")
						dane.bogus = dane_answer.bogus;
					elseif dane_answer.secure then
						log("debug", "Got additional secure TLSA")
						for _, dane_record in ipairs(dane_answer) do
							t_insert(dane, dane_record);
						end
					end
					if n == 0 then
						if dane then
							host_session.dane = dane;
							if #dane > 0 and dane.bogus then
								-- Got at least one non-bogus reply,
								-- This should trigger a failure if one of them did not match
								log("warn", "Ignoring bogus replies");
								dane.bogus = nil;
							end
							if #dane == 0 and dane.bogus == nil then
								-- Got no usable data
								host_session.dane = false;
							end
						end
						return cb(host_session);
					end
				end, ("_%d._tcp.%s."):format(record.srv.port, record.srv.target), "TLSA");
			end
		end, "_xmpp-server._tcp."..name..".", "SRV");
		return true;
	elseif host_session.direction == "outgoing" then
		-- Prosody has already done SRV lookups for outgoing session, so check if those are secure
		local srv_hosts = host_session.srv_hosts;
		if not ( srv_hosts and srv_hosts.answer and srv_hosts.answer.secure ) then
			return; -- No secure SRV records, fall back to non-DANE mode
			-- Empty response were not kept by older mod_s2s/s2sout
		end
		-- Do TLSA lookup for currently selected SRV record
		local srv_choice = srv_hosts[host_session.srv_choice or 0] or { target = idna_to_ascii(host_session.to_host), port = 5269 };
		log("debug", "Querying TLSA record for %s:%d", srv_choice.target, srv_choice.port);
		host_session.dane = dns_lookup(function(answer)
			if answer and ((answer.secure and #answer > 0) or answer.bogus) then
				srv_choice.dane = answer;
			else
				srv_choice.dane = false;
			end
			host_session.dane = srv_choice.dane;
			return cb(host_session);
		end, ("_%d._tcp.%s."):format(srv_choice.port, srv_choice.target), "TLSA");
		return true;
	end
end

local function pause(host_session)
	host_session.log("debug", "Pausing connection until DANE lookup is completed");
	host_session.conn:pause()
end

local function resume(host_session)
	host_session.log("debug", "DANE lookup completed, resuming connection");
	host_session.conn:resume()
end

if have_async then
	function pause(host_session)
		host_session.log("debug", "Pausing connection until DANE lookup is completed");
		local wait, done = async.waiter();
		host_session._done_waiting_for_dane = done;
		wait();
	end
	local function _resume(_, host_session)
		if host_session._done_waiting_for_dane then
			host_session.log("debug", "DANE lookup completed, resuming connection");
			host_session._done_waiting_for_dane();
			host_session._done_waiting_for_dane = nil;
		end
	end
	function resume(host_session)
		-- Something about the way luaunbound calls callbacks is messed up
		if host_session._done_waiting_for_dane then
			module:add_timer(0, _resume, host_session);
		end
	end
end

function module.add_host(module)
	local function on_new_s2s(event)
		local host_session = event.origin;
		if host_session.type == "s2sout" or host_session.type == "s2sin" then
			return; -- Already authenticated
		end
		if host_session.dane ~= nil then
			return; -- Already done DANE lookup
		end
		dane_lookup(host_session, resume);
		-- Let it run in parallell until we need to check the cert
	end

	-- New outgoing connections
	module:hook("stanza/http://etherx.jabber.org/streams:features", on_new_s2s, 501);
	module:hook("s2sout-authenticate-legacy", on_new_s2s, 200);

	-- New incoming connections
	module:hook("s2s-stream-features", on_new_s2s, 10);

	module:hook("s2s-authenticated", function(event)
		local session = event.session;
		if session.dane and type(session.dane) == "table" and next(session.dane) ~= nil and not session.secure then
			-- TLSA record but no TLS, not ok.
			-- TODO Optional?
			-- Bogus replies should trigger this path
			-- How does this interact with Dialback?
			session:close({
				condition = "policy-violation",
				text = "Encrypted server-to-server communication is required but was not "
					..((session.direction == "outgoing" and "offered") or "used")
			});
			return false;
		end
		-- Cleanup
		session.srv_hosts = nil;
	end);
end

-- Compare one TLSA record against a certificate
local function one_dane_check(tlsa, cert, log)
	local select, match, certdata = tlsa.select, tlsa.match;

	if select == 0 then
		certdata = pem2der(cert:pem());
	elseif select == 1 and cert.pubkey then
		certdata = pem2der(cert:pubkey());
	else
		log("warn", "DANE selector %s is unsupported", tlsa:getSelector() or select);
		return;
	end

	if match == 1 then
		certdata = hashes.sha256(certdata);
	elseif match == 2 then
		certdata = hashes.sha512(certdata);
	elseif match ~= 0 then
		log("warn", "DANE match rule %s is unsupported", tlsa:getMatchType() or match);
		return;
	end

	if #certdata ~= #tlsa.data then
		log("warn", "Length mismatch: Cert: %d, TLSA: %d", #certdata, #tlsa.data);
	end
	return certdata == tlsa.data;
end

module:hook("s2s-check-certificate", function(event)
	local session, cert, host = event.session, event.cert, event.host;
	if not cert then return end
	local log = session.log or module._log;
	local dane = session.dane;
	if type(dane) ~= "table" then
		if dane == nil and dane_lookup(session, resume) then
			pause(session);
			dane = session.dane;
		end
	end
	if type(dane) == "table" then
		local match_found, supported_found;
		for i = 1, #dane do
			local tlsa = dane[i].tlsa;
			log("debug", "TLSA #%d: %s", i, tostring(tlsa))
			local use = tlsa.use;

			if enabled_uses:contains(use) then
				-- DANE-EE or PKIX-EE
				if use == 3 or use == 1 then
					-- Should we check if the cert subject matches?
					local is_match = one_dane_check(tlsa, cert, log);
					if is_match ~= nil then
						supported_found = true;
					end
					if is_match and use == 1 and session.cert_chain_status ~= "valid" then
						-- for usage 1, PKIX-EE, the chain has to be valid already
						log("debug", "PKIX-EE TLSA matches untrusted certificate");
						is_match = false;
					end
					if is_match then
						log("info", "DANE validated ok for %s using %s", host, tlsa:getUsage());
						session.cert_identity_status = "valid";
						if use == 3 then -- DANE-EE, chain status equals DNSSEC chain status
							session.cert_chain_status = "valid";
						end
						match_found = true;
						dane.matching = tlsa;
						break;
					end
				-- DANE-TA or PKIX-CA
				elseif use == 2 or use == 0 then
					supported_found = true;
					local chain = session.conn:socket():getpeerchain();
					for c = 1, #chain do
						local cacert = chain[c];
						local is_match = one_dane_check(tlsa, cacert, log);
						if is_match ~= nil then
							supported_found = true;
						end
						if is_match and not cacert:issued(cert, unpack(chain)) then
							is_match = false;
						end
						if is_match and use == 0 and session.cert_chain_status ~= "valid" then
							-- for usage 0, PKIX-CA, identity and chain has to be valid already
							is_match = false;
						end
						if is_match then
							log("info", "DANE validated ok for %s using %s", host, tlsa:getUsage());
							if use == 2 then -- DANE-TA
								session.cert_identity_status = "valid";
								if cert_verify_identity(host, "xmpp-server", cert) then
									session.cert_chain_status = "valid";
									-- else -- TODO Check against SRV target?
								end
							end
							match_found = true;
							dane.matching = tlsa;
							break;
						end
					end
					if match_found then break end
				end
			end
		end
		if supported_found and not match_found or dane.bogus then
			-- No TLSA matched or response was bogus
			local why = "No TLSA matched certificate";
			if dane.bogus then
				why = "Bogus: "..tostring(dane.bogus);
			end
			log("warn", "DANE validation failed for %s: %s", host, why);
			session.cert_identity_status = "invalid";
			session.cert_chain_status = "invalid";
		end
	else
		if session.cert_chain_status == "valid" and session.cert_identity_status ~= "valid"
		and session.srv_hosts and session.srv_hosts.answer and session.srv_hosts.answer.secure then
			local srv_hosts, srv_choice, srv_target = session.srv_hosts, session.srv_choice;
			for i = srv_choice or 1, srv_choice or #srv_hosts do
				srv_target = session.srv_hosts[i].target:gsub("%.?$","");
				log("debug", "Comparing certificate with Secure SRV target %s", srv_target);
				srv_target = nameprep(idna_to_unicode(srv_target));
				if srv_target and cert_verify_identity(srv_target, "xmpp-server", cert) then
					log("info", "Certificate for %s matches Secure SRV target %s", host, srv_target);
					session.cert_identity_status = "valid";
					return;
				end
			end
		end
	end
end);

-- Telnet command
if module:get_option_set("modules_enabled", {}):contains("admin_telnet") then
	module:depends("admin_telnet"); -- Make sure the env is there
	local def_env = module:shared("admin_telnet/env");

	local function annotate(session, line)
		line = line or {};
		table.insert(line, "--");
		if session.dane == nil then
			table.insert(line, "No DANE attempted, probably insecure SRV response");
		elseif session.dane == false then
			table.insert(line, "DANE failed or response was insecure");
		elseif type(session.dane) ~= "table" then
			table.insert(line, "Waiting for DANE records...");
		elseif session.dane.matching then
			table.insert(line, "Matching DANE record:\n|       " .. tostring(session.dane.matching));
		else
			table.insert(line, "DANE records:\n|       " .. tostring(session.dane));
		end
		return table.concat(line, " ");
	end

	function def_env.s2s:show_dane(...)
		return self:show(..., annotate);
	end
end

