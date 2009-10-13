use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 2 }

foreach my $lang (qw(fr ja)) {
    dotest($lang, "$lang.format", Format => sub {
	return "    $_[1]>$_[2]" if $_[1] =~ /^so/;
	return "<$_[1]\n" if $_[1] =~ /^eo/;
	undef });
}    

1;

