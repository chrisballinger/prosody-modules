---
depends:
- 'mod\_track\_muc\_joins'
summary: Limit rate of outgoing unsolicited messages
...

Introduction
============

This module limits the rate of outgoing unsolicited messages. A message
counts as "unsolicited" if the receiving user hasn't added the sending
user to their roster.

The module depends on [mod\_track\_muc\_joins] in order to allow sent
messages to joined MUC rooms.

Configuration
=============

``` {.lua}
unsolicited_messages_per_minute = 10
```
