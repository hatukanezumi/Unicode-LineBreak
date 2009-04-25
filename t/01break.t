use strict;
use Test::More;
require "t/t.pl";

BEGIN { plan tests => 9 }

foreach my $lang (qw(ar el fr ja ja-a ko ru th zh)) {
    dotest($lang, $lang);
}    

1;

