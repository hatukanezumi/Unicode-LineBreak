use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 10 }

foreach my $lang (qw(ar el fr ja ja-a ko ru vi vi-decomp zh)) {
    dotest($lang, $lang);
}    

1;

