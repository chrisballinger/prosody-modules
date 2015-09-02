---
labels:
- 'Stage-Beta'
summary: Limit presence stanzas to save traffic
...

Introduction
============

For most people 'presence' (status changes) of contacts make up most of
the traffic received by their client. However much of the time it is not
essential to have highly accurate presence information.

This module automatically cuts down on presence traffic when clients
indicate they are inactive (using the [CSI protocol](mod_csi.html)).

This is extremely valuable for mobile clients that wish to save battery
power while in the background.

Configuration
=============

Just load the module (e.g. in modules\_enabled). There are no
configuration options.

Compatibility
=============

  ----- -------
  0.9   Works
  ----- -------
