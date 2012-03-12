# -*- perl -*-
# -*- coding: utf-8 -*-
#
# 00GraphemeBreakTest.txt - Test suite provided by Unicode Consortium.
#
# Passed by GraphemeBreakTest-6.1.0.txt (2011-12-07, 17:54:39 UTC), except
# 50 surrogate cases.
#

use strict;
use Test::More;
use Encode qw(decode is_utf8);
use Unicode::LineBreak;
use Unicode::GCString;

BEGIN {
    my $tests = 0;
    if (open IN, 'test-data/GraphemeBreakTest.txt') {
	my $desc = '';
	while (<IN>) {
	    s/\s*#\s*(.*)//;
	    if ($. <= 2) {
		$desc .= " $1";
		chomp $desc;
	    }
	    next unless /\S/;
	    $tests++;
	}
	close IN;
	if ($tests) {
	    plan tests => $tests;
	    diag $desc;
	} else {
	    plan skip_all => 'test-data/GraphemBreakTest.txt is empty.';
	}
    } else {
	plan skip_all => 'test-data/GraphemeBreakTest.txt found at '.
	    'http://www.unicode.org/Public/ is required.';
    }
}

my $lb = Unicode::LineBreak->new(
				 LegacyCM => 'YES',
				 ViramaAsJoiner => 'NO',
				);

open IN, 'test-data/GraphemeBreakTest.txt';

while (<IN>) {
    chomp $_;
    s/\s*#\s*(.*)$//;
    my $desc = $1;
    next unless /\S/;

    SKIP: {
	skip "subtests including surrogate", 1
	    if /\bD[89AB][0-9A-F][0-9A-F]\b/;

	s/\s*÷$//;
	s/^÷\s*//;

	my $s = join '',
	    map {
		$_ = chr hex "0x$_";
		$_ = decode('iso-8859-1', $_) unless is_utf8($_);
		$_;
	    }
	    split /\s*(?:÷|×)\s*/, $_;

	is join(' ÷ ',
	    map {
		 join ' × ',
		 map { sprintf '%04X', ord $_ }
		 split //, $_->as_string;
	    }
	    @{Unicode::GCString->new($s, $lb)}
	  ), $_, $desc;
    }
}

close IN;

