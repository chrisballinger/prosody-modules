---
summary: S2S connection override
...

# Introduction

This module is similar to [mod\_srvinjection] but less of an hack.

# Configuration

``` lua
-- In the global section

modules_enabled = {
    --- your other modules
    "s2soutinjection";
}

s2s_connect_overrides = {
    -- This one will use the default port, 5269
    ["example.com"] = "xmpp.server.local";

    -- To set a different port:
    ["another.example"] = { "non-standard-port.example", 9999 };
}
```

# Compatibility

Requires 0.9.x or later.
