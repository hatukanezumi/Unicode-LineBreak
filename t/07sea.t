use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 1 }

if (Unicode::LineBreak::Thai::supported()) {
    diag("libthai supported.");
    dotest('th', 'th');
} else {
    diag("libthai not supported.");
    dotest('th.al', 'th.al');
}

1;

