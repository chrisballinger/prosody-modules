---
labels:
- 'Stage-Alpha'
summary: 'XEP-0357: Cloud push notifications'
---

Introduction
============

This is an implementation of the server bits of [XEP-0357: Push
Notifications](http://xmpp.org/extensions/xep-0357.html). It allows
clients to register an "app server" which is notified about new messages
while the user is offline or disconnected. Implementation of the "app
server" is not included[^1].

Details
=======

App servers are notified about offline messages.

Configuration
=============

  Option                            Default   Description
  --------------------------------- --------- ------------------------------------------------------------------
  `push_notification_with_body`     `false`   Whether or not to send the message body to remote pubsub node.
  `push_notification_with_sender`   `false`   Whether or not to send the message sender to remote pubsub node.

There are privacy implications for enabling these options because
plaintext content and metadata will be shared with centralized servers
(the pubsub node) run by arbitrary app developers.

Installation
============

Same as any other module.

Configuration
=============

Configured in-band by supporting clients.

[^1]: The service which is expected to forward notifications to
    something like Google Cloud Messaging or Apple Notification Service
