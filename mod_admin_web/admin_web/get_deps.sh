#!/bin/sh
JQUERY_VERSION="1.10.2"
STROPHE_VERSION="1.1.2"
BOOTSTRAP_VERSION="1.4.0"
ADHOC_COMMITISH="87bfedccdb91e2ff7cfb165e989e5259c155b513"

cd www_files/js

rm -f jquery-$JQUERY_VERSION.min.js
wget http://code.jquery.com/jquery-$JQUERY_VERSION.min.js || exit 1

rm -f adhoc.js
wget -O adhoc.js "http://git.babelmonkeys.de/?p=adhocweb.git;a=blob_plain;f=js/adhoc.js;hb=$ADHOC_COMMITISH" || exit 1

rm -f strophe.min.js
wget https://raw.github.com/strophe/strophe.im/gh-pages/strophejs/downloads/strophejs-$STROPHE_VERSION.tar.gz && tar xzf strophejs-$STROPHE_VERSION.tar.gz strophejs-$STROPHE_VERSION/strophe.min.js --strip-components=1 && rm strophejs-$STROPHE_VERSION.tar.gz || exit 1

cd ../css
rm -f bootstrap-$BOOTSTRAP_VERSION.min.css
wget https://raw.github.com/twbs/bootstrap/v$BOOTSTRAP_VERSION/bootstrap.min.css -O bootstrap-$BOOTSTRAP_VERSION.min.css || exit 1
