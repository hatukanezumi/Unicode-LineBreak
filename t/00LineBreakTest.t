#
# 00LineBreakTest.txt - Test suite provided by Unicode Consortium.
#
# Result with LineBreakTest-6.0.0.txt (2010-08-30, 21:08:43 GMT):
#
#Failed Test         Stat Wstat Total Fail  Failed  List of Failed
#-------------------------------------------------------------------------------
#t/00LineBreakTest.t   30  7680  5401   30   0.56%  969 971 973 975 1113 1115
#                                                   1117 1119 2545 2547 3845
#                                                   3847 3989 3991 4417 4419
#                                                   5203 5212 5217 5303-5308
#                                                   5310-5314

use strict;
use Test::More;
use Encode qw(decode is_utf8);
use Unicode::LineBreak qw(:all);

BEGIN {
    my $tests = 0;
    if (open IN, 'testin/LineBreakTest.txt') {
	while (<IN>) {
	    s/\s*#.*//;
	    next unless /\S/;
	    $tests++;
	}
	close IN;
	plan tests => $tests;
    } else {
	plan skip_all => 'testin/LineBreakTest.txt found at '.
	    'http://www.unicode.org/Public/ is required.';
    }
}

my $result;

sub format {
    my $self = shift;
    my $ev = shift;
    my $str = shift;

    if ($ev eq 'sot') {
	$self->{'T'} = [];
    }
    if ($ev =~ /^so/) {
	$self->{'L'} = '';
    } elsif ($ev eq '') {
	$self->{'L'} = $str;
    } elsif ($ev =~ /^eo/) {
	$self->{'L'} .= $str;
	push @{$self->{'T'}}, $self->{'L'};
    }
    if ($ev eq 'eot') {
	$result = join ' ÷ ',
	map { join ' × ',
	      map { sprintf '%04X', ord $_ }
	      grep { length $_ }
	      split /(.)/s, "$_" }
	@{$self->{'T'}};
    }
    undef;
}

my $lb = Unicode::LineBreak->new(
				 BreakIndent => 'NO',
				 ColumnsMax => 1,
				 Format => \&format,
				 LegacyCM => 'NO',
				 TailorEA => [[1..65532] => EA_N],
			      );

open IN, 'testin/LineBreakTest.txt';

while (<IN>) {
    chomp $_;
    s/\s*#.*//;
    next unless /\S/;

    s/\s*÷$//;
    s/^×\s*//;
    my $s = join '',
	    map {
		$_ = sprintf '%c', hex "0x$_";
		$_ = decode('iso-8859-1', $_) unless is_utf8($_);
		$_;
	    }
	    split /\s*(?:÷|×)\s*/, $_;

    $lb->break($s);
    is ($result, $_);
}

close IN;

