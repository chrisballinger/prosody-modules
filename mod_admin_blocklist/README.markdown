---
summary: Block s2s connections based on admin blocklists
...

This module uses the blocklists set by admins for blocking s2s
connections.

So if an admin blocks a bare domain using [Blocking Command][xep191]
via [mod\_blocklist] then no s2s connections will be allowed to or from
that domain.
