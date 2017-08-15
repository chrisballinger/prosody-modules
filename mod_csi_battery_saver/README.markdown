---
description: CSI module to save battery on mobile devices
labels:
- 'Stage-Alpha'
---

Stanzas are queued in a buffer until either an "important" stanza is
encountered or the buffer becomes full. Then all queued stanzas are sent
at the same time. This way, nothing is lost or reordered while still
allowing for power usage savings by not requiring mobile clients to
bring up their radio for unimportant stanzas.

`IQ` stanzas, smacks "stanzas" and `message` stanzas containing a body are
considered important. Groupchat messages must set a subject or have
the user's username or nickname in their messages to count as "important".
`Presence` stanzas are not "important".

All buffered stanzas that allow timestamping are properly stamped to
reflect their original send time, see [XEP-0203].

Use with other CSI plugins such as [mod_throttle_presence],
[mod_filter_chatstates] or [mod_csi_pump] is *not* supported.
Please use this module instead of [mod_csi_pump] if you want timestamping
and properly handled carbon copies.

The internal stanza buffer of this module is hardcoded to 100 stanzas.
