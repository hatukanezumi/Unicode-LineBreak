use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 1 }

if (Unicode::LineBreak::SouthEastAsian::supported()) {
    diag("SA word segmentation supported.");
    dotest('th', 'th');
} else {
    diag("SA word segmentation not supported.");
    dotest('th.al', 'th.al');
}

1;

