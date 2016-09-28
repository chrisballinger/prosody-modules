---
labels:
- 'Stage-Beta'
summary: Delegate roster management to an external service
...

NOTE: THIS MODULE IS RELEASED UNDER THE MOZILLA PUBLIC LICENSE VERSION 2.

Normally the XMPP server will store and maintain the users' contact
rosters. This module lets you delegate roster management to an external
service.

Prosody will make an HTTP request to fetch the roster from the external
service. The service will need to notify Prosody whenever a user's roster
changes, so that Prosody can fetch a new roster for that user.

Configuring this module
-----------------------

This module relies on `mod_storage_memory` and `mod_block_subscriptions`.

In `.parts/prosody/etc/prosody/prosody.cfg.lua`, where your particular
`VirtualHost` is being configured, add the following:

    modules_enabled = {
        "http_roster_admin",
        "block_subscriptions",
        "storage_memory",
        "http_files"
    }
    modules_disabled = {
         -- Prosody will get the roster from the backend app,
         -- so we disable the default roster module.
        "roster"
    }
    storage = { roster = "memory" }
    http_roster_url = "http://localhost/contacts/%s" -- %s will be replaced by an URL-encoded username

The `http_roster_url` parameter needs to be configured to point to the
URL in the backend application which returns users' contacts rosters.

In this URL, the pattern `%s` is replaced by an URL-encoded username.

When the user *john* then connects to Prosody, and `http_roster_url` is
set to “http://app.example.org/contacts/%s”, then Prosody will make a
GET request to http://app.example.org/contacts/john

Notifying Prosody of roster changes
***********************************

The external service needs to notify Prosody whenever a user's roster
changes. To do this, it must make an HTTP POST request to either:

* http://localhost:5280/roster_admin/refresh
* https://localhost:5281/roster_admin/refresh

Make sure that the "http_files" module is enabled in Prosody's configuration,
for the above URLs to served.

Ports 5280/5281 can be firewalled and the web server (i.e. Apache or Nginx)
can be configured to reverse proxy those URLs to for example
https://example.org/http-bind.

The contents of the POST should be a JSON encoded array of usernames whose
rosters have changed.

For example, if user ‘john’ became friends with ‘aaron’, both john’s
contact list and aaron’s contact lists have changed:

```
    ["john", "aaron"]
```

When the operation is complete Prosody will reply with a summary of the
operation - a JSON object containing:

* **status**: either “ok” (success) or “error” (operation completely failed)
* **message**: A human-readable message (for logging and debugging purposes)
* **updated**: The number of rosters successfully updated
* **errors**: The number of rosters that failed to update

Example:

```
    {
        "status":  "ok",
        "message": "roster update complete",
        "updated": 2,
        "errors":  0
    }
```

Prosody may also return status codes `400` or `500` in case of errors (such
as a missing/malformed body).
