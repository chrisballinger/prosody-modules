---
labels:
- 'Stage-Beta'
- 'Type-Storage'
- ArchiveStorage
summary: XML archive storage
...

Introduction
============

This module implements stanza archives using files, similar to the
default "internal" storage.

Details
=======

Refer to [Prosodys data storage
documentation](https://prosody.im/doc/storage).

Note that this module does not implement the "keyval" storage method and
can't be used by anything other than archives, eg MAM and MUC logs.

Compatibility
=============

  --------- -------------
  \>=0.10   Should work
  --------- -------------
