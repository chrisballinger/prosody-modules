---
labels:
- 'Stage-Alpha'
summary: 'XEP-0357: Cloud push notifications'
...

Introduction
============

This is an implementation of the server bits of [XEP-357:
Push](http://xmpp.org/extensions/xep-357.html). It allows clients to
register an "app server" which is notified about new messages while the
user is offline or disconnected. Implementation of the "app server",
which is expected to forward notifications to something like Google
Cloud Messaging or Apple Notification Service.

Details
=======

App servers are notified about offline messages.

Installation
============

Same as any other module.

Configuration
=============

Configured in-band by supporting clients.

Future
======

Adding support for sending notifications for users who are online but
not currently connected, such as when `mod_smacks` is keeping their
session alive, should be added.
