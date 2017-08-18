---
description: CSI module to save battery on mobile devices
labels:
- 'Stage-Alpha'
---

Please use this module instead of [mod_csi_pump] if you want timestamping,
properly handled carbon copies, support for handling encrypted messages and
correctly handled smacks events.

If smacks is used on the same server this needs at least version [f70c02c14161]
of the smacks module! There could be message reordering on resume otherwise.

Stanzas are queued in a buffer until either an "important" stanza is
encountered or the buffer becomes full. Then all queued stanzas are sent
at the same time. This way, nothing is lost or reordered while still
allowing for power usage savings by not requiring mobile clients to
bring up their radio for unimportant stanzas.

`IQ` stanzas, and `message` stanzas containing a body or being encypted
and all nonzas are considered important. Groupchat messages must set a
subject or have the user's username or nickname in their messages to count
as "important". `Presence` stanzas are always not "important".

All buffered stanzas that allow timestamping are properly stamped to
reflect their original send time, see [XEP-0203].

Use with other CSI plugins such as [mod_throttle_presence],
[mod_filter_chatstates] or [mod_csi_pump] is *not* supported.

The internal stanza buffer of this module is hardcoded to 100 stanzas.

Configuration
=============

  Option                              Default           Description
  ----------------------------------  ---------- -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  `csi_battery_saver_filter_muc`      false      Controls whether all muc messages having a body should be considered as important (false) or only such containing the user's room nic (true). Warning: you should only set this to true if your users can live with muc messages being delayed several minutes. 


[f70c02c14161]: //hg.prosody.im/prosody-modules/raw-file/f70c02c14161/mod_smacks/mod_smacks.lua