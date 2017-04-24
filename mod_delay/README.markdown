---
labels:
- 'Stage-Alpha'
summary: Add "XEP-0203 Delayed Delivery"-tags to every message stanza
...

Introduction
============

This module adds "Delayed Delivery"-tags to every message stanza passing
the server containing the current time on that server.

This adds accurate message timings even when the message is delayed by slow networks
on the receiving client or by any event.

Compatibility
=============

  ----- -----------------------------------------------------
  0.10  Works
  ----- -----------------------------------------------------


Clients
=======

Clients that support XEP-0203 (among others):

-   Gajim
-   Conversations
-   Yaxim
