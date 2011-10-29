use strict;
use Test::More;
require "t/lf.pl";

BEGIN { plan tests => 15 }

foreach my $lang (qw(fr ja quotes)) {
    do5tests($lang, $lang);
}    

1;

