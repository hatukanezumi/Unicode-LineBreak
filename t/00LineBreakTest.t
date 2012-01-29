# -*- perl -*-
# -*- coding: utf-8 -*-
#
# 00LineBreakTest.txt - Test suite provided by Unicode Consortium.
#
# Passed by LineBreakTest-6.0.0.txt (2010-08-30, 21:08:43 UTC).
# Passed by LineBreakTest-6.1.0d12.txt (2011-09-16, 22:24:58 UTC).
# Passed by LineBreakTest-6.1.0d19.txt (2011-12-07, 01:05:50 UTC).
#

use strict;
use Test::More;
use Encode qw(decode is_utf8);
use Unicode::LineBreak qw(:all);

BEGIN {
    my $tests = 0;
    if (open IN, 'test-data/LineBreakTest.txt') {
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
	    plan skip_all => 'test-data/LineBreakTest.txt is empty.';
	}
    } else {
	plan skip_all => 'test-data/LineBreakTest.txt found at '.
	    'http://www.unicode.org/Public/ is required.';
    }
}

my $lb = Unicode::LineBreak->new(
				 BreakIndent => 'NO',
				 ColMax => 1,
				 EAWidth => [[1..65532] => EA_N],
				 Format => undef,
				 LegacyCM => 'NO',
			      );

open IN, 'test-data/LineBreakTest.txt';

while (<IN>) {
    chomp $_;
    s/\s*#\s*(.*)$//;
    my $desc = $1;
    next unless /\S/;

    s/\s*÷$//;
    s/^×\s*//;

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
		 split //, $_;
	    }
	    $lb->break($s)
       ), $_, $desc;
}

close IN;

