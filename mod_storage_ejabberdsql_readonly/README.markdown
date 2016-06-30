---
labels:
- 'Type-Storage'
- 'Stage-Alpha'
summary: Ejabberd SQL Read-only Storage Module
...

Introduction
============

This is a storage backend using Ejabberd’s SQL backend. It depends on
[LuaDBI](https://prosody.im/doc/depends#luadbi)

This module only works in read-only, and was made to be used by
[mod\_migrate](https://modules.prosody.im/mod_migrate.html) to migrate
from Ejabberd’s SQL backend.

Configuration
=============

Copy the module to the prosody modules/plugins directory.

In Prosody's configuration file, set:

    storage = "ejabberdsql_readonly"

EjabberdSQL options are the same as the
[https://prosody.im/doc/modules/mod\_storage\_sql](SQL ones):

Compatibility
=============

  ------- ---------------------------
  trunk   Works
  ------- ---------------------------
  0.10    Untested, but should work
  ------- ---------------------------
  0.9     Does not work
  ------- ---------------------------
