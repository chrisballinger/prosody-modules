---
description: HTTP File Upload
labels: 'Stage-Alpha'
---

Introduction
============

This module implements [XEP-0363], which lets clients upload files
over HTTP.

Configuration
=============

mod\_http\_upload relies on Prosodys HTTP server and mod\_http for
serving HTTP requests. See [Prosodys HTTP server documentation][doc:http]
for information about how to configure ports, HTTP Host names etc.

The module can be added as a new Component definition:

``` {.lua}
Component "upload.example.org" "http_upload"
```

Alternatively it can be added to `modules_enabled` like other modules.

Limits
------

A maximum file size can be set by:

``` {.lua}
http_upload_file_size_limit = 123 -- bytes
```

Default is 1MB (1024\*1024).

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
