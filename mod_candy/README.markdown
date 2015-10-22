---
labels:
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

You then need to download Candy and unpack it into the www\_files
directory, for example with curl:

    cd www_files
    curl -OL https://github.com/candy-chat/candy/releases/download/v2.0.0/candy-2.0.0.zip
    unzip candy-2.0.0.zip

After the module has been loaded, Candy will by default be reachable
from `http://example.com:5280/candy/`

Compatibility
=============

  ------- -------
  trunk   Works
  0.9     Works
  ------- -------
