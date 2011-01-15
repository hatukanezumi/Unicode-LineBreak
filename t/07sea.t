use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 1 }

my $sea = Unicode::LineBreak::SouthEastAsian::supported();
if ($sea) {
    diag "SA word segmentation supported. $sea";
    dotest('th', 'th', ComplexBreaking => "YES");
} else {
    SKIP: { skip "SA word segmentation not supported.", 1 }
}
1;

