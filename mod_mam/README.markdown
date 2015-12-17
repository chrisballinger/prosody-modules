---
labels:
- 'Stage-Beta'
summary: 'XEP-0313: Message Archive Management'
...

Introduction
============

Implementation of [XEP-0313: Message Archive Management].

Details
=======

This module will archive all messages that match the simple rules setup
by the user, and allow the user to access this archive.

Usage
=====

First copy the module to the prosody plugins directory.

Then add "mam" to your modules\_enabled list:

``` {.lua}
modules_enabled = {
    -- ...
    "mam",
    -- ...
}
```

Configuration
=============

Storage backend
---------------

mod\_mam uses the store "archive2"[\^1]. See [Prosodys data storage
documentation][doc:storage] for information on how to configure storage.

For example, to use mod\_storage\_sql:

``` {.lua}
storage = {
  archive2 = "sql";
}
```

Query size limits
-----------------

    max_archive_query_results = 20;

This is the largest number of messages that are allowed to be retrieved
in one request *page*. A query that does not fit in one page will
include a reference to the next page, letting clients page through the
result set. Setting large number is not recomended, as Prosody will be
blocked while processing the request and will not be able to do anything
else.

Message matching policy
-----------------------

The MAM protocol includes a way for clients to control what messages
should be stored. This allows users to enable or disable archiving by
default or for specific contacts. This module will log no messages by
default, for privacy concerns. If you decide to change this, you should
inform your users.

``` {.lua}
default_archive_policy = false
```

  `default_archive_policy =`   Meaning
  ---------------------------- ------------------------------------------------------
  `false`                      Store no messages. This is the default.
  `"roster"`                   Store messages to/from contacts in the users roster.
  `true`                       Store all messages.

Compatibility
=============

  ------- ---------------
  trunk   Works
  0.10    Works [^2]
  0.9     Unsupported
  0.8     Does not work
  ------- ---------------

[^1]: Might be changed to "mam" at some point

[^2]: requires a storage driver with archive support, eg
    mod\_storage\_sql in 0.10
