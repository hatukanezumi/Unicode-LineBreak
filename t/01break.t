use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 8 }

foreach my $lang (qw(ar el fr ja ja-a ko ru zh)) {
    dotest($lang, $lang);
}    

1;

