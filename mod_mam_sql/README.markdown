---
labels:
- 'Stage-Alpha'
- Deprecated
summary: 'XEP-0313: Message Archive Management using SQL'
...

**Note:** This module is unsupported and not up to date with the MAM
specification

Introduction
============

This is an old fork of mod\_mam with the purpose of figuring out and
testing an appropriate schema for future inclusion in prosodys
mod\_storage\_sql. That work is currently available in
mod\_storage\_sql2, pending merging with mod\_storage\_sql.

It talks SQL directly, bypassing prosodys storage layer.

It is no longer maintained and is unlikely to work with modern clients.

Details
=======

See [mod\_mam](mod_mam.md) for details.

Usage
=====

First copy the module to the prosody plugins directory.

Then add "mam\_sql" to your modules\_enabled list:

        modules_enabled = {
                        -- ...
                        "mam_sql",
                        -- ...
            }

You should probably run the SQL to create the archive table/indexes:

    CREATE TABLE `prosodyarchive` (
            `host` TEXT,
            `user` TEXT,
            `store` TEXT,
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `when` INTEGER,
            `with` TEXT,
            `resource` TEXT,
            `stanza` TEXT
    );
    CREATE INDEX `hus` ON `prosodyarchive` (`host`, `user`, `store`);
    CREATE INDEX `with` ON `prosodyarchive` (`with`);
    CREATE INDEX `thetime` ON `prosodyarchive` (`when`);

(**NOTE**: I ran the following SQL to initialize the table/indexes on
MySQL):

    CREATE TABLE prosodyarchive (
      `host`     VARCHAR(1023) NOT NULL,
      `user`     VARCHAR(1023) NOT NULL,
      `store`    VARCHAR(1023) NOT NULL,
      `id`       INTEGER PRIMARY KEY AUTO_INCREMENT,
      `when`     INTEGER     NOT NULL,
      `with`     VARCHAR(2047) NOT NULL,
      `resource` VARCHAR(1023),
      `stanza`   TEXT        NOT NULL
    );
    CREATE INDEX hus ON prosodyarchive (host, user, store);
    CREATE INDEX `with` ON prosodyarchive (`with`);
    CREATE INDEX thetime ON prosodyarchive (`when`);

You may want to tweak the column sizes a bit; I did for my own purposes.

Configuration
=============

This module uses the same configuration settings that
[mod\_mam](mod_mam.md) does, in addition to the [SQL storage
settings](http://prosody.im/doc/modules/mod_storage_sql). You may also
name the SQL connection settings 'mam\_sql' if you want.

Compatibility
=============

  ------- ----------------------
  0.8     ?
  0.9     Works
  0.10    Use mod\_mam instead
  trunk   Use mod\_mam instead
  ------- ----------------------
