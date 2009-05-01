use strict;
use Test::More;
require "t/lf.pl";

BEGIN { plan tests => 6 }

foreach my $lang (qw(fr ja)) {
    dotest($lang, "$lang.plain", "PLAIN");
    dotest($lang, "$lang.fixed", "FIXED");
    dotest($lang, "$lang.flowed", "FLOWED");
}    

1;

