#
# 00LineBreakTest.txt - Test suite provided by Unicode Consortium.
#
# Result with LineBreakTest-6.0.0.txt (2010-08-30, 21:08:43 UTC):
#
#Failed Test         Stat Wstat Total Fail  Failed  List of Failed
#-------------------------------------------------------------------------------
#t/00LineBreakTest.t   30  7680  5401   30   0.56%  969 971 973 975 1113 1115
#                                                   1117 1119 2545 2547 3845
#                                                   3847 3989 3991 4417 4419
#                                                   5203 5212 5217 5303-5308
#                                                   5310-5314
#
# Result with LineBreakTest-6.1.0d12.txt (2011-09-16, 22:24:58 UTC):
#
#Failed Test         Stat Wstat Total Fail  Failed  List of Failed
#-------------------------------------------------------------------------------
#t/00LineBreakTest.t   30  7680  5693   30   0.53%  997 999 1001 1003 1145 1147
#                                                   1149 1151 2765 2767 4101
#                                                   4103 4249 4251 4689 4691
#                                                   5495 5504 5509 5595-5600
#                                                   5602-5606

use strict;
use Test::More;
use Encode qw(decode is_utf8);
use Unicode::LineBreak qw(:all);

BEGIN {
    my $tests = 0;
    if (open IN, 'test-data/LineBreakTest.txt') {
	while (<IN>) {
	    s/\s*#.*//;
	    next unless /\S/;
	    $tests++;
	}
	close IN;
	plan tests => $tests;
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

