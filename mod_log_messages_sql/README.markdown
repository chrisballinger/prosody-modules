This module logs messages to a SQL database.

SQL connection options are configured in a `message_log_sql` option,
which has the same syntax as the `sql` option for
[mod_storage_sql][doc:modules:mod_storage_sql].

You will need to create the following table in the configured database:

``` sql
CREATE TABLE `prosodyarchive` (
        `host` TEXT,
        `user` TEXT,
        `store` TEXT,
        `id` INTEGER PRIMARY KEY AUTOINCREMENT,
        `when` INTEGER,
        `with` TEXT,
        `resource` TEXT,
        `stanza` TEXT);
```
