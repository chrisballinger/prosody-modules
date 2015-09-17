Introduction
============

This module provides a space for clients to upload files over HTTP, as
used by [Conversations](http://conversations.im/).

Configuration
=============

mod\_http\_upload relies on Prosodys HTTP server and mod\_http for
serving HTTP requests. See [Prosodys HTTP server
documentation](https://prosody.im/doc/http) for information about how to
configure ports, HTTP Host names etc.

The module can either be configured as a component or added to an
existing host or component. Possible configuration variants are as
follows:

Component
---------

You can configure it as a standalone component:

    Component "upload.example.org" "http_upload"

Existing component
------------------

Or add it to an existing component:

    Component "proxy.example.org" "proxy65"
    modules_enabled = {
      "http_upload";
    }

On VirtualHosts
---------------

Or load it directly on hosts:

    -- In the Global section or under a specific VirtualHosts line
    modules_enabled = {
      -- other modules
      "http_upload";
    }

Limits
------

A maximum file size can be set by:

``` {.lua}
http_upload_file_size_limit = 10 * 1024 * 1024 -- this is 10MB in bytes
```

Compatibility
=============

Works with Prosody 0.9.x and later.
