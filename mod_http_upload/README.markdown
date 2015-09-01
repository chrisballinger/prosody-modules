Introduction
============

This module provides a space for clients to upload files over HTTP, as
used by [Conversations](http://conversations.im/).

Configuration
=============

The module can either be configured as a component or added to an
existing host or component.

Component
---------

Standalone component:

    Component "upload.example.org" "http_upload"

Existing component
------------------

    Component "proxy.example.org" "proxy65"
    modules_enabled = {
      "http_upload";
    }

On VirtualHosts
---------------

    -- In the Global section or under a specific VirtualHosts line
    modules_enabled = {
      -- other modules
      "http_upload";
    }
