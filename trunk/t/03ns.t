use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 2 }

dotest('ja-k', 'ja-k', ColumnsMax => 72);
dotest('ja-k', 'ja-k.ns', TailorLB => [KANA_NONSTARTERS() => LB_ID()],
       ColumnsMax => 72);

1;

