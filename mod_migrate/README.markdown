---
summary: prosodyctl cross storage driver migration tool
...

Introduction
============

This module adds a command to `prosodyctl` for copying data between
storage drivers.

Usage
=====

    prosodyctl mod_migrate example.com <source-store>[-<store-type>] <target-driver> [users]*

`<source-store>` would be e.g. `accounts` or `private`. To migrate
archives, the optional suffix `<store-type>` would be set to `archive`,
so e.g. `archive2-archive` or `muc_log-archive`.

`<target-driver>` is the storage driver to copy data to, sans the
`mod_storage_` prefix.

The process is something like this:

1.  Decide on the future configuration and add for example SQL
    connection details to your prosody config, but don't change the
    `store` option yet.
2.  With Prosody shut down, run
    `prosodyctl mod_migrate example.com accounts sql`
3.  Repeat for each store, substituting 'accounts'. E.g. vcards,
    private...
4.  Change the [`storage` configuration](https://prosody.im/doc/storage)
    to use the new driver.
5.  Start prosody again.

Examples
========

    for store in accounts roster private blocklist vcard archive2-archive; do
      prosodyctl migrate example.com $store sql
    done

Compatibility
=============

Should work with 0.8 and later.
