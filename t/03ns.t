use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 2 }

dotest('ja-k', 'ja-k', MaxColumns => 72);
dotest('ja-k', 'ja-k.ns', NSKanaAsID => 'YES', MaxColumns => 72);

1;

