---
summary: Keep track of joined chat rooms
...

# Introduction

This module attempts to keep track of what MUC chat rooms users have
joined. It's not very useful on its own, but can be used by other
modules to influence decisions.

# Usage

Rooms joined and the associated nickname is kept in a table field
`rooms_joined` on the users session.

An example:

``` lua
local jid_bare = require"util.jid".bare;

module:hook("message/full", function (event)
    local stanza = event.stanza;
    local session = prosody.full_sessions[stanza.attr.to];
    if not session then
        return -- No such session
    end

    local joined_rooms = session.joined_rooms;
    if not joined_rooms then
        return -- This session hasn't joined any rooms at all
    end

    -- joined_rooms is a map of room JID -> room nickname
    local nickname = joined_rooms[jid_bare(stanza.attr.from)];
    if nickname then
        session.log("info", "Got a MUC message from %s", stanza.attr.from);

        local body = stanza:get_child_text("body");
        if body and body:find(nickname, 1, true) then
            session.log("info", "The message contains my nickname!");
        end
    end
end);
```
