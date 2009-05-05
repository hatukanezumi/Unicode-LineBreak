use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 2 }

dotest('ja-k', 'ja-k', ColumnsMax => 72);
dotest('ja-k', 'ja-k.ns', NSKanaAsID => 'YES', ColumnsMax => 72);

1;

