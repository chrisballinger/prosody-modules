---
summary: Subscribe to Atom and RSS feeds over pubsub
...

Introduction
============

This module allows Prosody to fetch Atom and RSS feeds for you, and push
new results to subscribers over XMPP.

This module also implements a
[PubSubHubbub](http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html)
subscriber, allowing updates be delivered without polling for supporting
feed publishers.

Configuration
=============

This module needs to be be loaded together with
[mod\_pubsub][doc:modules:mod\_pubsub].

For example, this is how you could add it to an existing pubsub
component:

``` lua
Component "pubsub.example.com" "pubsub"
modules_enabled = { "pubsub_feeds" }

feeds = {
  planet_jabber = "http://planet.jabber.org/atom.xml";
  prosody_blog = "http://blog.prosody.im/feed/atom.xml";
}
```

This example creates two nodes, 'planet\_jabber' and 'prosody\_blog'
that clients can subscribe to using
[XEP-0060](http://xmpp.org/extensions/xep-0060.html). Results are in
[ATOM 1.0 format](http://atomenabled.org/) for easy consumption.

  Option                 Description
  ---------------------- -------------------------------------------------------------------------
  feeds                  A list of virtual nodes to create and their associated Atom or RSS URL.
  feed\_pull\_interval   Number of minutes between polling for new results (default 15)
  use\_pubsubhubub       If PubSubHubbub should be enabled, true by default.

Compatibility
=============

  ----- -------
  0.9   Works
  ----- -------
