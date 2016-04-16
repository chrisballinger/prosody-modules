---
summary: HTTP directory listing
...

Introduction
============

This module generates directory listings when invoked by
`mod_http_files`. See [documentation on
`mod_http_files`](http://prosody.im/doc/modules/mod_http_files).

Configuration
=============

The module itself doesn't have any configuration of its own, just enable
the it along with `mod_http_files`.

    modules_enabled = {
        ...

        "http_files";
        "http_dir_listing";
    }

    http_dir_listing = true;

The layout, CSS and icons in the `resources/` directory can be
customized or replaced. All resources are cached in memory when the
module is loaded and the images are inlined in the CSS.

Compatibility
=============

  ------- --------------
  trunk   Works
  0.9     Works
  0.8     Doesn't work
  ------- --------------
