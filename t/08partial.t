use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 12 }

foreach my $len (qw(2 76 998)) {
    foreach my $lang (qw(ja-a amitagyong ecclesiazusae)) {
	dotest_partial($lang, $lang, $len);
    }
    if (Unicode::LineBreak::SouthEastAsian::supported()) {
	dotest_partial('th', 'th', $len);
    } else {
	dotest_partial('th', 'th.al', $len);
    }
}
