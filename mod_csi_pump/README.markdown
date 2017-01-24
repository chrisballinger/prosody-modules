---
description: Lossless CSI module
labels:
- 'Stage-Alpha'
---

Stanzas are queued in a buffer until either an "important" stanza is
encountered or the buffer becomes full. Then all queued stanzas are sent
at the same time. This way, nothing is lost or reordered while still
allowing for power usage savings by not requiring mobile clients to
bring up their radio for unimportant stanzas.
