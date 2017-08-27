Introduction
============

This module produces a list of enabled HTTP "apps" exposed from Prosody
at `http://example.org:5280/`, e.g. [mod\_http\_muc\_log],
[mod\_http\_files][doc:modules:mod_http_files] or
[mod\_admin\_web]. If you think Prosodys default "root" web page (a
404 error usually) is boring, this might be the module for you! :)

Configuration
=============

Install and enable like any other module. Also see [Prosodys HTTP
documentation](https://prosody.im/doc/http).

``` {.lua}
modules_enabled = {
  -- other modules
  "http_index";
}

-- optional, defaults to a file next to the module
http_index_template = "/path/to/template.html"
```
