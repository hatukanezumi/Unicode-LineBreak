use strict;
use Encode qw(decode_utf8 encode_utf8);
use Unicode::LineBreak;

$Unicode::LineBreak::Config = {
    CharactersMax => 998,
    ColumnsMin => 0,
    ColumnsMax => 76,
    Context => 'NONEASTASIAN',
    Format => 'DEFAULT',
    HangulAsAL => 'NO',
    LegacyCM => "YES",
    Newline => "\n",
    NSKanaAsID => "NO",
    SizingMethod => "DEFAULT",
    UrgentBreaking => 'NONBREAK',
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

1;

