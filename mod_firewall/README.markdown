---
labels:
- 'Stage-Alpha'
summary: 'A rule-based stanza filtering module'
...

------------------------------------------------------------------------

**Note:** mod\_firewall is in its very early stages. This documentation
is liable to change, and some described functionality may be missing,
incomplete or contain bugs.

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

Specifying rule sets
--------------------

Firewall rules should be written into text files, e.g. `ruleset.pfw` file.
One or more rule files can be specified in the configuration using:

    firewall_scripts = { "path/to/ruleset.pfw", "path/to/ruleset2.pfw" }

If multiple files are specified and they both add rules to the same chains,
each file's rules will be processed in order, but the order of files is undefined.

Conditions
----------

All conditions must come before any action in a rule block. The
condition name is followed by a colon (':'), and the value to test for.

A condition can be preceded or followed by `NOT` to negate its match.
For example:

    NOT FROM: user@example.com
    KIND NOT: message

Some conditions do not take parameters, and these should end with just a
question mark, like:

    IN ROSTER?

### Zones

A 'zone' is one or more hosts or JIDs. It is possible to match when a
stanza is entering or leaving a zone, while at the same time not
matching traffic passing between JIDs in the same zone.

Zones are defined at the top of a script with the following syntax (they
are not part of a rule block):

    %ZONE myzone: host1, host2, user@host3, foo.bar.example

There is an automatic zone named `$local`, which automatically includes
all of the current server's active hosts (including components). It can
be used to match stanzas entering or leaving the current server.

A host listed in a zone also matches all users on that host (but not
subdomains).

The following zone-matching conditions are supported:

  Condition    Matches
  ------------ ------------------------------------------
  `ENTERING`   When a stanza is entering the named zone
  `LEAVING`    When a stanza is leaving the named zone

### Lists

It is possible to create or load lists of strings for use in scripts. For example, you might load a JID blacklist,
a list of malware URLs or simple words that you want to filter messages on.

  List type    Example
  -----------  -----------------------
  memory       %LIST spammers: memory
  file         %LIST spammers: file:/etc/spammers.txt
  http         %LIST spammers: http://example.com/spammers.txt

#### CHECK LIST

Checks whether a simple expression is found in a given list.

Example:

    %LIST blacklist: file:/etc/prosody/blacklist.txt

    # Rule to block presence subscription requests from blacklisted JIDs
    KIND: presence
    TYPE: subscribe
    CHECK LIST: blacklist contains $<@from>
    BOUNCE=policy-violation (Your JID is blacklisted)

#### SCAN

SCAN allows you to search inside a stanza for a given pattern, and check each result against a list. For example,
you could scan a message body for words and check if any of the words are found in a given list.

Before using SCAN, you need to define a search location and a pattern. The search location uses the same 'path'
format as documented under the 'INSPECT' condition. Patterns can be any valid Lua pattern.

To use the above example:

    # Define a search location called 'body' which fetches the text of the 'body' element
    %SEARCH body: body#
    # Define a pattern called 'word' which matches any sequence of letters
    %PATTERN word: [A-Za-z]+
    # Finally, we also need our list of "bad" words:
    %LIST badwords: file:/etc/prosody/bad_words.txt
    
    # Now we can use these to SCAN incoming stanzas
    # If it finds a match, bounce the stanza
    SCAN: body for word in badwords
    BOUNCE=policy-violation (This word is not allowed!)

#### COUNT

COUNT is similar to SCAN, in that it uses a defined SEARCH and breaks it up according to a PATTERN. Then it
counts the number of results.

For example, to block every message with more than one URL:

    # Define a search location called 'body' which fetches the text of the 'body' element
    %SEARCH body: body#
    # Define a pattern called 'url' which matches HTTP links
    %PATTERN url: https?://%S+
    
    COUNT: url in body > 1
    BOUNCE=policy-violation (Up to one HTTP URL is allowed in messages)

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

### Sender/recipient matching

  Condition     Matches
  ------------- -------------------------------------------------------
  `FROM`        The JID in the 'from' attribute matches the given JID.
  `TO`          The JID in the 'to' attribute matches the given JID.
  `TO SELF`     The stanza is sent by any of a user's resources to their own bare JID.
  `TO FULL JID` The stanza is addressed to a valid full JID on the local server (full JIDs include a resource at the end, and only exist for the lifetime of a single session, therefore the recipient must be online, or this check will not match).

The TO and FROM conditions both accept wildcards in the JID when the wildcard
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
    BOUNCE=not-allowed (The username 'admin' is reserved.)

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

### Roster

These functions access the roster of the recipient (only). Therefore they cannot (currently)
be used in some chains, such as for outgoing messages (the recipient may be on another server).

Performance note: this check can potentially cause storage access (especially if the recipient
is currently offline), so you may want to limit its use in high-traffic situations, and place
it below other checks (such as a rate limiter).

#### IN ROSTER

Tests whether the sender is in the recipient's roster.

    IN ROSTER?

#### IN ROSTER GROUP

Tests whether the sender is in the recipient's roster, and in the named group.

    IN ROSTER GROUP: Friends

#### SUBSCRIBED

Tests whether the recipient is subscribed to the sender, ie will receive
presence updates from them.

Note that this *does* work, regardless of direction and which chain is
used, since both the sender and the recipient will have mirrored roster
entries.

### Groups

Using Prosody's mod\_groups it is possible to define groups of users on the server. You can
match based on these groups in firewall rules.

  Condition         Matches
  ----------------- ----------------------------
  `FROM GROUP`      When the stanza is being sent from a member of the named group
  `TO GROUP`        When the stanza is being sent to a member of the named group
  `CROSSING GROUPS` When the stanza is being sent between users of different named groups

#### CROSSING GROUPS

The `CROSSING GROUPS` condition takes a comma-separated list of groups to check. If the
sender and recipient are not in the same group (only the listed groups are checked), then the
this condition matches and the stanza is deemed to be crossing between groups.

For example, if you had three groups: Engineering, Marketing and Employees. All users are
members of the 'Employees' group, and the others are for employees of the named department only.

To prevent employees in the marketing department from communicating with engineers, you could use
the following rule:

```
CROSSING GROUPS: Marketing, Engineering
BOUNCE=policy-violation (no communication between these groups is allowed!)
```

This works, even though both the users are in the 'Employees' group, because that group is not listed
in the condition.

In the above example, a user who is member of both groups is not restricted.

#### SENT DIRECTED PRESENCE TO SENDER

This condition matches if the recipient of a stanza has previously sent directed presence to the sender of the stanza. This
is often done in XMPP to exchange presence information with JIDs that are not on your roster, such as MUC rooms.

This condition does not take a parameter - end the condition name with a question mark:

    # Rule to bounce messages from senders not in the roster who haven't been sent directed presence
    NOT IN ROSTER?
    NOT SENT DIRECTED PRESENCE TO SENDER?
    BOUNCE=service-unavailable

### Admins

Prosody allows certain JIDs to be declared as administrators of a host, component or the whole server.

  Condition        Matches
  ---------------- -------------------------------------------------------------------------------------
  `TO ADMIN`       When the recipient of the stanza is admin of the current host
  `FROM ADMIN`     When the sender of the stanza is admin of the current host
  `FROM ADMIN OF`  When the sender of the stanza is an admin of the named host on the current server
  `TO ADMIN OF`    When the recipient of the stanza is an admin of the named host on the current server

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

#### Dynamic limits

Sometimes you may want to have multiple throttles in a single condition, using some property of the session or stanza
to determine which throttle to use. For example, you might have a limit for incoming stanzas, but you want to limit by
sending JID, instead of all incoming stanzas sharing the same limit.

You can use the 'on' keyword for this, like so:

    LIMIT: normal on EXPRESSION

For more information on expressions, see the section later in this document.

Each value of 'EXPRESSION' has to be tracked individually in a table, which uses a small amount of memory. To prevent
memory exhaustion, the number of tracked values is limited to 1000 by default. You can override this by setting the
maximum number of table entries when you define the rate:

    %RATE normal: 2 (burst 3) (entries 4096)

Old values are automatically removed from the tracking table. However if the tracking table becomes full, new entries
will be rejected - it will behave as if the rate limit was reached, even for values that have not been seen before. Since
this opens up a potential denial of service (innocent users may be affected if malicious users can fill up the tracking
table within the limit period). You can choose to instead "fail open", and allow the rate limit to be temporarily bypassed
when the table is full. To choose this behaviour, add `(allow overflow)` to the RATE definition.

### Session marking

It is possible to 'mark' sessions (see the MARK_ORIGIN action below). To match stanzas from marked sessions, use the
`ORIGIN_MARKED` condition.

  Condition                       Description
  ------------------------------- ---------------------------------------------------------------
  ORIGIN MARKED: markname         Matches if the origin has been marked with 'markname'.
  ORIGIN MARKED: markname (Xs)    Matches if the origin has been marked with 'markname' within the past X seconds.

Example usage:

    # This rule drops messages from sessions that have been marked as spammers in the past hour
    ORIGIN MARKED: spammer (3600s)
    DROP.

    # This rule marks the origin session as a spammer if they send a message to a honeypot JID
    KIND: message
    TO: honeypot@example.com
    MARK ORIGIN=spammer

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
  `PASS.`                 Stop executing actions and rules on this stanza, and let it through this chain and any calling chains.
  `DROP.`                 Stop executing actions and rules on this stanza, and discard it.
  `DEFAULT.`              Stop executing actions and rules on this stanza, prevent any other scripts/modules from handling it, to trigger the appropriate default "unhandled stanza" behaviour. Do not use in custom chains (it is treated as PASS).
  `REDIRECT=jid`          Redirect the stanza to the given JID.
  `REPLY=text`            Reply to the stanza (assumed to be a message) with the given text.
  `BOUNCE.`               Bounce the stanza with the default error (usually service-unavailable)
  `BOUNCE=error`          Bounce the stanza with the given error (MUST be a defined XMPP stanza error, see [RFC6120](http://xmpp.org/rfcs/rfc6120.html#stanzas-error-conditions).
  `BOUNCE=error (text)`   As above, but include the supplied human-readable text with a description of the error
  `COPY=jid`              Make a copy of the stanza and send the copy to the specified JID. The copied stanza flows through Prosody's routing code, and as such is affected by firewall rules. Be careful to avoid loops.
  `FORWARD=jid`           Forward a copy of the stanza to the given JID (using XEP-0297). The stanza will be sent from the current host's JID.

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
  `MARK ORIGIN=mark`        Marks the originating session with the given flag.
  `UNMARK ORIGIN=mark`      Removes the given mark from the origin session (if it is set).

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

More info about expressions can be found below.

Chains
------

Rules are grouped into "chains", which are injected at particular points in Prosody's routing code.

Available built-in chains are:

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
  `JUMP CHAIN=name`        Switches chains, and passes the stanza through the rules in chain 'name'. If the new chain causes the stanza to be dropped/redirected, the current chain halts further processing.
  `RETURN.`                Stops executing the current chain and returns to the parent chain. For built-in chains, equivalent to PASS. RETURN is implicit at the end of every chain.

It is possible to jump to chains defined by other scripts and modules.

Expressions
-----------

Some conditions and actions in rules support "expressions" in their parameters (their documentation will indicate if this is the case). Most parameters
are static once the firewall script is loaded and compiled internally, however parameters that allow expressions can be dynamically calculated when a
rule is being run.

There are two kinds of expression that you can use: stanza expressions, and code expressions.

### Stanza expressions

Stanza expressions are of the form `$<...>`, where `...` is a stanza path. For syntax of stanza paths, see the documentation for the 'INSPECT' condition
above.

Example:

    LOG=Matched a stanza from $<@from> to $<@to>

There are built in functions which can be applied to the output of a stanza expression, by appending the pipe ('|') operator, followed by the function
name. These functions are:

  Function     Description
  ------------ ---------------------------------------
  bare         Given a JID, strip any resource
  node         Return the node ('user part') of a JID
  host         Return the host ('domain') part of a JID
  resource     Return the resource part of a JID

For example, to apply a rate limit to stanzas per sender domain:

    LIMIT normal on $<@from|domain>

If the path does not match (e.g. the element isn't found, or the attribute doesn't exist) or any of the functions fail to produce an output (e.g. an invalid
JID was passed to a function that only handles valid JIDs) the expression will return the text `<undefined>`. You can override this by ending the expression
with a double pipe ('||') followed by a quoted string to use as a default instead. E.g. to default to the string "normal" when there is no 'type' attribute:

    LOG=Stanza type is $<@type||"normal">

### Code expressions

Code expressions use `$(...)` syntax. Code expressions are powerful, and allow unconstrained access to Prosody's internal environment. Therefore
code expressions are typically for advanced use-cases only. You may want to refer to Prosody's [developer documentation](https://prosody.im/doc/developers)
for more information. In particular, within code expressions you may access the 'session' object, which is the session object of the origin of the stanza,
and the 'stanza' object, which is the stanza being considered within the current rule. Whatever value the expression returns will be converted to a string.

Example to limit stanzas per session type:

    LIMIT: normal on $(session.type)
