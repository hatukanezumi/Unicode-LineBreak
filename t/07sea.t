use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 1 }

my $libthai = Unicode::LineBreak::Thai::supported();
if ($libthai) {
    diag("libthai $libthai supported.");
    dotest('th', 'th');
} else {
    diag("libthai not supported.");
    dotest('th.al', 'th.al');
}

1;

