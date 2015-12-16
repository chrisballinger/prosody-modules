---
labels:
- 'Stage-Alpha'
summary: 'XEP-0313: Message Archive Management for MUC'
...

Introduction
============

This module logs the conversation of chatrooms running on the server to
Prosody's archive storage. To access them you will need a client with
support for [XEP-0313: Message Archive Management] or a module such
as [mod\_http\_muc\_log].

Usage
=====

First copy the module to the prosody plugins directory.

Then add "mam\_muc" to your modules\_enabled list:

``` {.lua}
Component "conference.example.org" "muc"
modules_enabled = {
  "mam_muc",
}
storage = {
  -- This makes mod_mam_muc use the sql2 storage backend (others will use internal)
    -- which at the time of this writing is the only one supporting stanza archives
    muc_log = "sql2";
}
```

See [Prosodys data storage
documentation](https://prosody.im/doc/storage) for more info on how to
configure storage for different plugins.

Configuration
=============

Logging needs to be enabled for each room in the room configuration
dialog.

``` {.lua}
muc_log_by_default = true; -- Enable logging by default (can be disabled in room config)

muc_log_all_rooms = false; -- set to true to force logging of all rooms

-- This is the largest number of messages that are allowed to be retrieved in one MAM request.
max_archive_query_results = 20;

-- This is the largest number of messages that are allowed to be retrieved when joining a room.
max_history_messages = 1000;
```

Compatibility
=============

  ------- -----------------
  trunk   Works best
  0.10    Works partially
  0.9     Does not work
  0.8     Does not work
  ------- -----------------

Prosody trunk (after April 2014) has a major rewrite of the MUC module,
allowing easier integration. Without this (0.10), some features do not
work, such as correct advertising and join/part logging.
