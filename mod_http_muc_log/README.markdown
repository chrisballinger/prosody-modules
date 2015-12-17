---
labels:
- 'Stage-Beta'
summary: Provides a web interface to stored chatroom logs
...

Introduction
============

This module provides a built-in web interface to view chatroom logs
stored by [mod\_mam\_muc].

Installation
============

Same as any other module, be sure to include the HTML template
`http_muc_log.html` alongside `mod_http_muc_log.lua`.

Configuration
=============

For example:

``` lua
Component "conference.example.com" "muc"
modules_enabled = {
    "mam_muc";
    "http_muc_log";
}
storage = {
    muc_log = "sql"; -- for example
}
```

The web interface would then be reachable at the address:

    http://conference.example.com:5280/muc_log/

See [the page about Prosodys HTTP server][doc:http] for info about the
address.

Compatibility
=============

Requires Prosody 0.10 or above and a storage backend with support for
stanza archives. See [mod\_storage\_muc\_log] for using legacy data from
[mod\_muc\_log].
