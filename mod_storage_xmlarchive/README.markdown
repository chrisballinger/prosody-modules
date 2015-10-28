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

Configuration
=============

To use this with [mod\_mam] add this to your config:

``` lua
storage = {
    archive2 = "xmlarchive"
}
```

To use it with [mod\_mam\_muc] or [mod_http_muc_log]:

``` lua
storage = {
    muc_log = "xmlarchive"
}
```

Refer to [Prosodys data storage
documentation](https://prosody.im/doc/storage) for more information.

Note that this module does not implement the "keyval" storage method and
can't be used by anything other than archives.

Compatibility
=============

  ------ ---------------
  0.10   Works
  0.9    Maybe
  0.8    Does not work
  ------ ---------------
