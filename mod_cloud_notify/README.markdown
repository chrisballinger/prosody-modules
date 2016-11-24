---
labels:
- 'Stage-Beta'
summary: 'XEP-0357: Cloud push notifications'
---

Introduction
============

This is an implementation of the server bits of [XEP-0357: Push Notifications].
It allows clients to register an "app server" which is notified about new
messages while the user is offline, disconnected or the session is hibernated
by [mod_smacks]. 
Implementation of the "app server" is not included[^1].

Details
=======

App servers are notified about offline messages or messages waiting
in the smacks queue.

To cooperate with [mod_smacks] this module consumes some events:
"smacks-ack-delayed", "smacks-hibernation-start" and "smacks-hibernation-end".
These events allow this module to send out notifications for messages received
while the session is hibernated by [mod_smacks] or even when smacks
acknowledgements for messages are delayed by a certain amount of seconds
configurable with the [mod_smacks] setting "smacks_max_ack_delay".

The "smacks_max_ack_delay" setting allows to send out notifications to clients
which aren't already in smacks hibernation state (because the read timeout or
connection close didn't happen already) but also aren't responding to acknowledgement
request in a timely manner, thus allowing conversations to be smoother under such
circumstances.

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

Compatibility
=============

Should work with 0.9+.

[^1]: The service which is expected to forward notifications to
    something like Google Cloud Messaging or Apple Notification Service
[mod_smacks]: //modules.prosody.im/mod_smacks
