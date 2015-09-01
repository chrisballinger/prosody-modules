---
labels:
summary: prosodyctl cross storage driver migration tool
...

Description
===========

This module adds a command to `prosodyctl` for copying data between
storage drivers.

Usage:
`prosodyctl mod_migrate example.com <source-store> <target-driver> [users]*`

`<source-store>` would be e.g. `accounts` or `private`

`<target-driver>` is the storage driver to copy data to, sans the
`mod_storage_` prefix.

The process is something like this:

1.  Decide on the future configuration and add this to your prosody
    config.
2.  With Prosody shut down, run
    `prosodyctl mod_migrate example.com accounts sql`
3.  Repeat for each store, substituting 'accounts'. E.g. vcards,
    private...
4.  Change the `storage` configuration to use the new driver.
5.  Start prosody again.
