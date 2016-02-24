---
labels: Stage-Alpha
description: HTTP File Upload
...

Introduction
============

This module implements [XEP-0363], which lets clients upload files over
HTTP.

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
http_upload_file_size_limit = 123 -- bytes
```

Default is 10MB (10*1024*1024).

Path
----

By default, uploaded files are put in a sub-directory of the default
Prosody storage path (usually `/var/lib/prosody`). This can be changed:

``` {.lua}
http_upload_path = "/path/to/uploded/files"
```

Compatibility
=============

Works with Prosody 0.9.x and later.
