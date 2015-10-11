---
summary: Keepalive s2s connections
...

Introduction
============

This module periodically sends XEP-0199 ping requests to remote servers
to keep your connection alive.

Configuration
=============

Simply add the module to the `modules_enabled` list and specify your
desired servers in `keepalive_servers`. Optionally you can configure
the ping interval.

    modules_enabled = {
        ...
        "s2s_keepalive"
    }

    keepalive_servers = { "conference.prosody.im"; "rooms.swift.im" }
    keepalive_interval = "300" -- (in seconds, default is 60 )

Compatibility
=============

  ------- -----------------------
  0.10    Works
  ------- -----------------------
