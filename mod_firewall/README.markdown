---
labels:
- 'Stage-Alpha'
summary: 'A rule-based stanza filtering module'
...

------------------------------------------------------------------------

**Note:** mod\_firewall is in its very early stages. This documentation
is liable to change, and some described functionality may be missing,
incomplete or contain bugs. Feedback is welcome in the comments section
at the bottom of this page.

------------------------------------------------------------------------

Introduction
============

A firewall is an invaluable tool in the sysadmin's toolbox. However
while low-level firewalls such as iptables and pf are incredibly good at
what they do, they are generally not able to handle application-layer
rules.

The goal of mod\_firewall is to provide similar services at the XMPP
layer. Based on rule scripts it can efficiently block, bounce, drop,
forward, copy, redirect stanzas and more! Furthermore all rules can be
applied and updated dynamically at runtime without restarting the
server.

Details
=======

mod\_firewall loads one or more scripts, and compiles these to Lua code
that reacts to stanzas flowing through Prosody. The firewall script
syntax is unusual, but straightforward.

A firewall script is dominated by rules. Each rule has two parts:
conditions, and actions. When a stanza matches all of the conditions,
all of the actions are executed in order.

Here is a simple example to block stanzas from spammer@example.com:

    FROM: spammer@example.com
    DROP.

FROM is a condition, and DROP is an action. This is about as simple as
it gets. How about heading to the other extreme? Let's demonstrate
something more complex that mod\_firewall can do for you:

    %ZONE myorganisation: staff.myorg.example, support.myorg.example

    ENTERING: myorganisation
    KIND: message
    TIME: 12am-9am, 5pm-12am, Saturday, Sunday
    REPLY=Sorry, I am afraid our office is closed at the moment. If you need assistance, please call our 24-hour support line on 123-456-789.

This rule will reply with a short message whenever someone tries to send
a message to someone at any of the hosts defined in the 'myorganisation'
outside of office hours.

Firewall rules should be written to a `ruleset.pfw` file. Multiple such
rule files can be specified in the configuration using:

    firewall_scripts = { "path/to/ruleset.pfw" }

Conditions
----------

All conditions must come before any action in a rule block. The
condition name is followed by a colon (':'), and the value to test for.

A condition can be preceded or followed by `NOT` to negate its match.
For example:

    NOT FROM: user@example.com
    KIND NOT: message

### Zones

A 'zone' is one or more hosts or JIDs. It is possible to match when a
stanza is entering or leaving a zone, while at the same time not
matching traffic passing between JIDs in the same zone.

Zones are defined at the top of a script with the following syntax (they
are not part of a rule block):

    %ZONE myzone: host1, host2, user@host3, foo.bar.example

A host listed in a zone also matches all users on that host (but not
subdomains).

The following zone-matching conditions are supported:

  Condition    Matches
  ------------ ------------------------------------------
  `ENTERING`   When a stanza is entering the named zone
  `LEAVING`    When a stanza is leaving the named zone

### Stanza matching

  Condition   Matches
  ----------- ------------------------------------------------------------------------------------------------------------------------------------------------------------
  `KIND`      The kind of stanza. May be 'message', 'presence' or 'iq'
  `TYPE`      The type of stanza. This varies depending on the kind of stanza. See 'Stanza types' below for more information.
  `PAYLOAD`   The stanza contains a child with the given namespace. Useful for determining the type of an iq request, or whether a message contains a certain extension.
  `INSPECT`   The node at the specified path exists or matches a given string. This allows you to look anywhere inside a stanza. See below for examples and more.

#### Stanza types

  Stanza     Valid types
  ---------- ------------------------------------------------------------------------------------------
  iq         get, set, result, error
  presence   *available*, unavailable, probe, subscribe, subscribed, unsubscribe, unsubscribed, error
  message    normal, chat, groupchat, headline, error

**Note:** The type 'available' for presence does not actually appear in
the protocol. Available presence is signalled by the omission of a type.
Similarly, a message stanza with no type is equivalent to one of type
'normal'. mod\_firewall handles these cases for you automatically.

#### INSPECT

INSPECT takes a 'path' through the stanza to get a string (an attribute
value or text content). An example is the best way to explain. Let's
check that a user is not trying to register an account with the username
'admin'. This stanza comes from [XEP-0077: In-band
Registration](http://xmpp.org/extensions/xep-0077.html#example-4):

``` xml
<iq type='set' id='reg2'>
  <query xmlns='jabber:iq:register'>
    <username>bill</username>
    <password>Calliope</password>
    <email>bard@shakespeare.lit</email>
  </query>
</iq>
```

    KIND: iq
    TYPE: set
    PAYLOAD: jabber:iq:register
    INSPECT: {jabber:iq:register}query/username#=admin
    BOUNCE=not-allowed The username 'admin' is reserved.

That weird string deserves some explanation. It is a path, divided into
segments by '/'. Each segment describes an element by its name,
optionally prefixed by its namespace in curly braces ('{...}'). If the
path ends with a '\#' then the text content of the last element will be
returned. If the path ends with '@name' then the value of the attribute
'name' will be returned.

You can use INSPECT to test for the existence of an element or attribute,
or you can see if it is equal to a string by appending `=STRING` (as in the
example above). Finally,you can also test whether it matches a given Lua
pattern by using `~=PATTERN`.

INSPECT is somewhat slower than the other stanza matching conditions. To
minimise performance impact, always place it below other faster
condition checks where possible (e.g. above we first checked KIND, TYPE
and PAYLOAD matched before INSPECT).

### Sender/recipient matching

  Condition   Matches
  ----------- -------------------------------------------------------
  `FROM`      The JID in the 'from' attribute matches the given JID
  `TO`        The JID in the 'to' attribute matches the given JID

These conditions both accept wildcards in the JID when the wildcard
expression is enclosed in angle brackets ('\<...\>'). For example:

    # All users at example.com
    FROM: <*>@example.com

    # The user 'admin' on any subdomain of example.com
    FROM: admin@<*.example.com>

You can also use [Lua's pattern
matching](http://www.lua.org/manual/5.1/manual.html#5.4.1) for more
powerful matching abilities. Patterns are a lightweight
regular-expression alternative. Simply contain the pattern in double
angle brackets. The pattern is automatically anchored at the start and
end (so it must match the entire portion of the JID).

    # Match admin@example.com, and admin1@example.com, etc.
    FROM: <<admin%d*>>@example.com

**Note:** It is important to know that 'example.com' is a valid JID on
its own, and does **not** match 'user@example.com'. To perform domain
whitelists or blacklists, use Zones.

  Condition        Matches
  ---------------- ---------------------------------------------------------------
  `FROM_EXACTLY`   The JID in the 'from' attribute exactly matches the given JID
  `TO_EXACTLY`     The JID in the 'to' attribute exactly matches the given JID

These additional conditions do not support pattern matching, but are
useful to match the exact to/from address on a stanza. For example, if
no resource is specified then only bare JIDs will be matched. TO and FROM
match all resources if no resource is specified to match.

**Note:** Some chains execute before Prosody has performed any
normalisation or validity checks on the to/from JIDs on an incoming
stanza. It is not advisable to perform access control or similar rules
on JIDs in these chains (see the chain documentation for more info).

### Time and date

#### TIME

Matches stanzas sent during certain time periods.

  Condition   Matches
  ----------- -------------------------------------------------------------------------------------------
  TIME        When the current server local time is within one of the comma-separated time ranges given

    TIME: 10pm-6am, 14:00-15:00
    REPLY=Zzzz.

#### DAY

It is also possible to match only on certain days of the week.

  Condition   Matches
  ----------- -----------------------------------------------------------------------------------------------------
  DAY         When the current day matches one, or falls within a rage, in the given comma-separated list of days

Example:

    DAY: Sat-Sun, Wednesday
    REPLY=Sorry, I'm out enjoying life!

All times and dates are handled in the server's local time.

### Rate-limiting

It is possible to selectively rate-limit stanzas, and use rules to
decide what to do with stanzas when over the limit.

First, you must define any rate limits that you are going to use in your
script. Here we create a limiter called 'normal' that will allow 2
stanzas per second, and then we define a rule to bounce messages when
over this limit. Note that the `RATE` definition is not part of a rule
(multiple rules can share the same limiter).

    %RATE normal: 2 (burst 3)

    KIND: message
    LIMIT: normal
    BOUNCE=policy-violation (Sending too fast!)

The 'burst' parameter on the rate limit allows you to spread the limit
check over a given time period. For example the definition shown above
will allow the limit to be temporarily surpassed, as long as it is
within the limit after 3 seconds. You will almost always want to specify
a burst factor.

Both the rate and the burst can be fractional values. For example a rate
of 0.1 means only one event is allowed every 10 seconds.

The LIMIT condition actually does two things; first it counts against
the given limiter, and then it checks to see if the limiter over its
limit yet. If it is, the condition matches, otherwise it will not.

  Condition   Matches
  ----------- --------------------------------------------------------------------------------------------------
  `LIMIT`     When the named limit is 'used up'. Using this condition automatically counts against that limit.

**Note:** Reloading mod\_firewall resets the current state of any
limiters.

### Session marking

It is possible to 'mark' sessions (see the MARK_ORIGIN action below). To match stanzas from marked sessions, use the
`ORIGIN_MARKED` condition.

  Condition                       Description
  ------------------------------- ---------------------------------------------------------------
  ORIGIN_MARKED: markname         Matches if the origin has been marked with 'markname'.
  ORIGIN_MARKED: markname (Xs)    Matches if the origin has been marked with 'markname' within the past X seconds.

Example usage:

    # This rule drops messages from sessions that have been marked as spammers in the past hour
    ORIGIN_MARKED: spammer (3600s)
    DROP.

    # This rule marks the origin session as a spammer if they send a message to a honeypot JID
    KIND: message
    TO: honeypot@example.com
    MARK_ORIGIN=spammer

Actions
-------

Actions come after all conditions in a rule block. There must be at
least one action, though conditions are optional.

An action without parameters ends with a full-stop/period ('.'), and one
with parameters uses an equals sign ('='):

    # An action with no parameters:
    DROP.

    # An action with a parameter:
    REPLY=Hello, this is a reply.

### Route modification

The most common actions modify the stanza's route in some way. Currently
the first matching rule to do so will halt further processing of actions
and rules (this may change in the future).

  Action                  Description
  ----------------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------
  `PASS.`                 Stop executing actions and rules on this stanza, and let it through this chain.
  `DROP.`                 Stop executing actions and rules on this stanza, and discard it.
  `REDIRECT=jid`          Redirect the stanza to the given JID.
  `REPLY=text`            Reply to the stanza (assumed to be a message) with the given text.
  `BOUNCE.`               Bounce the stanza with the default error (usually service-unavailable)
  `BOUNCE=error`          Bounce the stanza with the given error (MUST be a defined XMPP stanza error, see [RFC6120](http://xmpp.org/rfcs/rfc6120.html#stanzas-error-conditions).
  `BOUNCE=error (text)`   As above, but include the supplied human-readable text with a description of the error
  `COPY=jid`              Make a copy of the stanza and send the copy to the specified JID. The copied stanza flows through Prosody's routing code, and as such is affected by firewall rules. Be careful to avoid loops.

**Note:** It is incorrect behaviour to reply to an 'error' stanza with another error, so BOUNCE will simply act the same as 'DROP' for stanzas that should not be bounced (error stanzas and iq results).

### Stanza modification

These actions make it possible to modify the content and structure of a
stanza.

  Action                   Description
  ------------------------ ------------------------------------------------------------------------
  `STRIP=name`             Remove any child elements with the given name in the default namespace
  `STRIP=name namespace`   Remove any child elements with the given name and the given namespace
  `INJECT=xml`             Inject the given XML into the stanza as a child element

### Sessions

It is possible to mark sessions, and then use these marks to match rules later on.

  Action                   Description
  ------------------------ --------------------------------------------------------------------------
  `MARK_ORIGIN=mark`        Marks the originating session with the given flag.
  `UNMARK_ORIGIN=mark`      Removes the given mark from the origin session (if it is set).

**Note:** Marks apply to sessions, not JIDs. E.g. if marking in a rule that matches a stanza received
over s2s, it is the s2s session that is marked.

It is possible to have multiple marks on an origin at any given time.

### Informational

  Action          Description
  --------------- ------------------------------------------------------------------------------------------------------------------------
  `LOG=message`   Logs the given message to Prosody's log file. Optionally prefix it with a log level in square brackets, e.g. `[debug]`

You can include expressions in log messages, using `$(...)` syntax. For example, to log the stanza that matched the rule, you can use $(stanza),
or to log just the top tag of the stanza, use $(stanza:top_tag()).

Example:

    # Log all stanzas to user@example.com:
    TO: user@example.com
    LOG=[debug] User received: $(stanza)

Chains
------

Rules are grouped into "chains", which are injected at particular points in Prosody's routing code.

Available chains are:

  Chain          Description
  -------------- -------------------------------------------------------------------------------------------
  deliver        Applies to stanzas delivered to local recipients (regardless of the stanza's origin)
  deliver_remote Applies to stanzas delivered to remote recipients (just before they leave the local server)
  preroute       Applies to incoming stanzas from local users, before any routing rules are applied

A chain is begun by a line `::name` where 'name' is the name of the chain you want the following rules to be
inserted into. If no chain is specified, rules are put into the 'deliver' chain.

It is possible to create custom chains (useful with the JUMP_CHAIN action described below). User-created
chains must begin with "user/", e.g. "user/spam_filtering".

Example of chain use:

    # example.com's firewall script
    
    # This line is optional, because 'deliver' is the default chain anyway:
    ::deliver
    
    # This rule matches any stanzas delivered to our local user bob:
    TO: bob@example.com
    DROP.
    
    # Oops! This rule will never match, because alice is not a local user,
    # and only stanzas to local users go through the 'deliver' chain:
    TO: alice@remote.example.com
    DROP.

    # Create a 'preroute' chain of rules (matched for incoming stanzas from local clients):
    ::preroute
    # These rules are matched for outgoing stanzas from local clients
    
    # This will match any stanzas sent to alice from a local user:
    TO: alice@remote.example.com
    DROP.

  Action                   Description
  ------------------------ ------------------------------------------------------------------------
  `JUMP_CHAIN=name`        Switches chains, and passes the stanza through the rules in chain 'name'. If the new chain causes the stanza to be dropped/redirected, the current chain halts further processing.
