---
summary: Cache presence incoming presence
...

Introduction
============

This module stores presence from users contact even when they are
offline, so that the client can see who is online faster when they sign
in, and won't have to wait for remote servers to reply.

Note that in its current form, the number of presence stanzas sent to a
client is doubled, as the client would get both the cached stanzas and
replies to presence probes. Also see [mod\_throttle\_presence].

By default, only binary (online or offline) state is stored. It can
optionally store the full presence but this requires much more memory
and bandwidth.

Configuration
=============

Just enable the module.

    modules_enabled = {
        -- more modules
        "presence_cache";
    }

Advanced configuration
======================

To enable *experimental* full stanza caching:

    presence_cache_full = false

This will usually double the presence data sent to clients, pending
support for deduplication.

TODO
====

-   Deduplication, i.e don's send stanzas that are identical to the last
    seen.
-   Cache invalidation or expiry, eg if a remote server goes down or is
    gone a long time.
-   Sending probes at some interval to keep the cache reasonably fresh.


