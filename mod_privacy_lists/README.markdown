---
labels:
- 'Stage-Beta'
summary: 'Privacy lists (XEP-0016) support'
...

Introduction
------------

Privacy lists are a flexible method for blocking communications.

Originally known as mod\_privacy and bundled with Prosody, this module
is being phased out in favour of the newer simpler blocking (XEP-0191)
protocol, implemented in [mod\_blocklist][doc:modules:mod_blocklist].

Configuration
-------------

None. Each user can specify their privacy lists using their client (if
it supports XEP-0016).

Compatibility
-------------

  ------ -------
  0.9    Works
  0.10   Works
  ------ -------
