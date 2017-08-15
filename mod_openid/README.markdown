---
labels:
- 'Stage-Alpha'
summary: Enables Prosody to act as an OpenID provider
...

Introduction
============

[OpenID](http://openid.net/) is an decentralized authentication
mechanism for the Web. mod\_openid turns Prosody into an OpenID
*provider*, allowing users to use their Prosody credentials to
authenticate with various third party websites.

Caveats
=======

mod\_openid can best be described as a **proof-of-concept**, it has
known deficiencies and should **not** be used in the wild as a
legitimate OpenID provider. mod\_openid was developed using the Prosody
0.4.x series, it has not been tested with the 0.5.x or later series.

Details
=======

OpenID works on the basis of a user proving to a third-party they wish
to authenticate with, an OpenID *relaying party*, that they have claim
or ownership over a URL, known as an OpenID *identifier*. mod\_openid
uses Prosody's built in HTTP server to provide every user with an OpenID
identifier of the form `http://host.domain.tld[:port]/openid/user`,
which would be the OpenID identifier of the user with a Jabber ID of
`user@host.domain.tld`.

Usage
=====

Simply add "mod\_openid" to your modules\_enabled list. You may then use
the OpenID identifier form as described above as your OpenID identifier.
The port Prosody's HTTP server will listen on is currently set as 5280,
meaning the full OpenID identifier of the user `romeo@montague.lit`
would be `http://montague.lit:5280/openid/romeo`.

Configuration
=============

mod\_openid has no configuration options as of this time.

TODO
====

The following is a list of the pending tasks which would have to be done
to make mod\_openid fully featured. They are generally ranked in order
of most importance with an estimated degree of difficulty.

1.  Support Prosody 0.6.x series (**Medium**)
2.  Refactor code (**Medium**)
    -   The code is pretty messy at the moment, it should be refactored
        to be more easily understood.

3.  Disable use of "user@domain" OpenID identifier form (*Easy*)
    -   This is a vestigial feature from the early design, allowing
        explicit specification of the JID. However the JID can be
        inferred from the simpler OpenID identifier form.

4.  Use a cryptographically secure Pseudo Random Number Generator (PRNG)
    (**Medium**)
    -   This would likely be accomplished using luacrypto which provides
        a Lua binding to the OpenSSL PRNG.

5.  Make sure OpenID key-value pairs get signed in the right order
    (***Hard***)
    -   It is important that the OpenID key-value responses be signed in
        the proper order so that the signature can be properly verified
        by the receiving party. This may be complicated by the fact that
        the iterative ordering of keys in a Lua table is not guaranteed
        for non-integer keys.

6.  Do an actual match on the OpenID realm (**Medium**)
    -   The code currently always returns true for matches against an
        OpenID realm, posing a security risk.

7.  Don't use plain text authentication over HTTP (***Hard***)
    -   This would require some Javascript to perform a digest.

8.  Return meaningful error responses (**Medium**)
    -   Most error responses are an HTTP 404 File Not Found, obviously
        something more meaningful could be returned.

9.  Enable Association (***Hard***)
    -   Association is a feature of the OpenID specification which
        reduces the number of round-trips needed to perform
        authentication.

10. Support HTTPS (**Medium**)
    -   With option to only allow authentication through HTTPS

11. Enable OpenID 1.1 compatibility (**Medium**)
    -   mod\_openid is designed from the OpenID 2.0 specification, which
        has an OpenID 1.1 compatibility mode.

12. Check specification compliance (**Medium**)
    -   Walk through the code and make sure it complies with the OpenID
        specification. Comment code as necessary with the relevant
        sections in the specification.

Once all these steps are done, mod\_openid could be considered to have
reached "beta" status and ready to real world use. The following are
features that would be nice to have in a stable release:

1.  Allow users to always trust realms (***Hard***)
2.  Allow users to remain logged in with a cookie (***Hard***)
3.  Enable simple registration using a user's vCard (**Medium**)
4.  More useful user identity page (***Hard***)
    -   Allow users to alter what realms they trust and what simple
        registration information gets sent to relaying parties by
        default.

5.  OpenID Bot (***Hard***)
    -   Offers all functionality of the user identity page management

6.  Better designed pages (*Easy*)
    -   Use semantic XHTML and CSS to allow for custom styling.
    -   Use the Prosody favicon.

Useful Links
============

-   [OpenID Specifications](http://openid.net/developers/specs/)
-   [OpenID on Wikipedia](http://en.wikipedia.org/wiki/OpenID)
