---
labels:
- 'Stage-Beta'
summary: Contact Addresses for XMPP Services
---

Introduction
============

This module lets you advertise various contact addresses for your XMPP
service via [XEP-0157].

Configuration
=============

Various types of contact addresses can be set via the single table
option `contact_info`. Each field is either a string or a list of
strings. Each string should be an URI.

An example showing all possible fields:

``` {.lua}
contact_info = {
  abuse = { "mailto:abuse@shakespeare.lit", "xmpp:abuse@shakespeare.lit" };
  admin = { "mailto:admin@shakespeare.lit", "xmpp:admin@shakespeare.lit" };
  feedback = { "http://shakespeare.lit/feedback.php", "mailto:feedback@shakespeare.lit", "xmpp:feedback@shakespeare.lit" };
  sales = "xmpp:bard@shakespeare.lit";
  security = "xmpp:security@shakespeare.lit";
  support = { "http://shakespeare.lit/support.php", "xmpp:support@shakespeare.lit" };
};
```

If not set, the `admins` option will be used.

Compatibility
=============

  ------ ---------------
  0.10   works
  0.9    works
  0.8    does not work
  ------ ---------------
