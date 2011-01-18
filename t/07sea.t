use strict;
use Test::More;
require "t/lb.pl";

BEGIN {
    require Unicode::LineBreak;
    if (Unicode::LineBreak::SouthEastAsian::supported()) {
	plan tests => 1;
    } else {
	plan skip_all => "SA word segmentation not supported.";
    }
}

diag "SA word segmentation supported. " .
    Unicode::LineBreak::SouthEastAsian::supported();
dotest('th', 'th', ComplexBreaking => "YES");

1;

