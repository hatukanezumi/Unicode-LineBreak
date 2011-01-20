use strict;
use Test::More;
require "t/lf.pl";

BEGIN { plan tests => 10 }

foreach my $lang (qw(fr ja)) {
    do5tests($lang, $lang);
}    

1;

