use strict;
use Encode qw(decode_utf8 encode_utf8);
use Unicode::LineBreak qw(:all);

$Unicode::LineBreak::Config = {
    CharactersMax => 998,
    ColumnsMin => 0,
    ColumnsMax => 76,
    Context => 'NONEASTASIAN',
    Format => 'SIMPLE',
    HangulAsAL => 'NO',
    LegacyCM => "YES",
    Newline => "\n",
    SizingMethod => "UAX11",
    TailorEA => [],
    TailorLB => [],
    UrgentBreaking => undef,
    UserBreaking => [],
};

sub dotest {
    my $in = shift;
    my $out = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = decode_utf8(join '', <IN>);
    close IN;
    my $lb = Unicode::LineBreak->new(@_);
    my $broken = encode_utf8($lb->break($instring));

    my $outstring = '';
    if (open OUT, "<testin/$out.out") {
	$outstring = join '', <OUT>;
	close OUT;
    } else {
	open XXX, ">testin/$out.xxx";
	print XXX $broken;
	close XXX;
    }

    is($broken, $outstring);
}    

sub dotest_partial {
    my $in = shift;
    my $out = shift;
    my $len = shift;

    my $lb = Unicode::LineBreak->new(@_);
    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = decode_utf8(join '', <IN>);
    close IN;

    my $broken = '';
    while ($instring) {
	my $p = substr($instring, 0, $len);
	if (length $instring < $len) {
	    $instring = '';
	} else {
	    $instring = substr($instring, $len);
	}
	$broken .= encode_utf8($lb->break_partial($p)); 
    }
    $broken .= encode_utf8($lb->break_partial(undef));

    my $outstring = '';
    if (open OUT, "<testin/$out.out") {
	$outstring = join '', <OUT>;
	close OUT;
    } else {
	open XXX, ">testin/$out.xxx";
	print XXX $broken;
	close XXX;
    }

    is($broken, $outstring);
}

sub dotest_array {
    my $in = shift;
    my $out = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = decode_utf8(join '', <IN>);
    close IN;
    my $lb = Unicode::LineBreak->new(@_);
    my @broken = map { encode_utf8("$_") } $lb->break($instring);

    my @outstring = ();
    if (open OUT, "<testin/$out.out") {
	@outstring = <OUT>;
	close OUT;
    } else {
	open XXX, ">testin/$out.xxx";
	print XXX join '', @broken;
	close XXX;
    }

    is_deeply(\@broken, \@outstring);
}    

1;

