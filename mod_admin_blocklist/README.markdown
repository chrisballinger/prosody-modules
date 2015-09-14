---
summary: Block s2s connections based on admin blocklists
...

This module uses the blocklists set by admins for blocking s2s
connections.

So if an admin blocks a bare domain using [Blocking
Command](http://xmpp.org/extensions/xep-0191.html) via
[mod\_blocklist](https://prosody.im/doc/modules/mod_blocklist) then no
s2s connections will be allowed to or from that domain.

Note that the module may need to be reloaded after a blocklist has been
updated.
