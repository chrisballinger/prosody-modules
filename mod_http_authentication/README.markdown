---
labels:
- 'Stage-Beta'
summary: Enforces HTTP Basic authentication across all HTTP endpoints served by Prosody
...

# mod_http_authentication

This module enforces HTTP Basic authentication across all HTTP endpoints served by Prosody.

## Configuration

Name                             Default                          Description
-------------------------------  -------------------------------  -----------------------------
minddistrict_http_credentials    "minddistrict:secretpassword"    The credentials that HTTP clients must provide to access the HTTP interface. Should be a string with the syntax "username:password".
unauthenticated_http_endpoints   { "/http-bind", "/http-bind/" }  A list of paths that should be excluded from authentication.

## Usage

This is a global module, so should be added to the global `modules_enabled` option in your config file. It applies to all HTTP virtual hosts.

## Known issues

The module use a new API in Prosody 0.10. This API currently has an open issue ([issue #554](https://prosody.im/issues/issue/554)) 
that means this module cannot be unloaded dynamically at runtime. In practice this shouldn't be an issue, and we will resolve the problem inside Prosody in due course.

## Details

By Kim Alvefur \<zash@zash.se\>
