---
summary: Serve Candy from prosody
...

Introduction
============

This is a very simple demo module showing how to serve a BOSH-using web
app from prosody.

Installation
============

[Install][doc:installing\_modules] and [enable][doc:modules\_enabled]
the module just like any other. Note the included HTML file in the
www\_files directory, this directory needs to be in the same place as
the module.

mod\_candy will automatically configure Candy for username and password
or anonymous login depending on the `authentication` option on the
current VirtualHost.

You then need to download Candy and unpack it into the www\_files
directory, for example with curl:

    cd www_files
    curl -OL https://github.com/candy-chat/candy/releases/download/v2.2.0/candy-2.2.0.zip
    unzip candy-2.2.0.zip

After the module has been loaded, Candy will by default be reachable
from `http://example.com:5280/candy/`. See [HTTP configuration][doc:http]
for more.

You can configure what rooms to join using either `candy_rooms` (an
array) or [mod\_default\_bookmarks]. By default, Candy will attempt to
join rooms that the current user has bookmarked.
If `candy_rooms` is not set, mod\_candy will attempt to find a MUC
component and join a room called "candy" there.  If there are no rooms
to join, then Candy will show an emtpy screen.

Compatibility
=============

  ------- -------
    trunk Works
     0.10 Works
      0.9 Works
  ------- -------
