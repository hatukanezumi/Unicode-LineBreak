use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 1 }

dotest('ko', 'ko.al', HangulAsAL => 'YES');

1;

