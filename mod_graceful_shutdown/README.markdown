This module is an experiment about a more graceful shutdown process.

Why
===

When shutting down, a number of sessions, connections and other things
are teared down. Due to all these things happening very quickly,
sometimes eg client unavailable notifications don't make it to all
remote contacts because the server-to-server connections are teared down
just after.

How
===

This module works by breaking the shutdown process into separate steps
with a brief pause between them.

It goes something like this

1.  Stop accepting new client connections.
2.  Close all client connections.
3.  Fire event for everything else.
4.  Tell `net.server` to quit the main loop.
5.  ???
6.  Still here? Kill itself.

