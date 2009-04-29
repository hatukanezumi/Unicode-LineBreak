use strict;
use Encode qw(decode_utf8 encode_utf8);
use Unicode::LineBreak;

$Unicode::LineBreak::Config = {
    Detect7bit => 'YES',
    Mapping => 'EXTENDED',
    Replacement => 'DEFAULT',
    Charset => 'UTF-8',
    Context => '',
    Format => 'DEFAULT',
    HangulAsAL => 'NO',
    Language => 'XX',
    LegacyCM => "YES",
    MaxColumns => 76,
    Newline => "\n",
    NSKanaAsID => "NO",
    OutputCharset => 'UTF-8',
    SizingMethod => "DEFAULT",
};

sub dotest {
    my $in = shift;
    my $out = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = decode_utf8(join '', <IN>);
    close IN;
    my $lb = Unicode::LineBreak->new(@_);
    my $broken = encode_utf8($lb->break($instring));
    #open XXX, ">testin/$out.xxx";
    #print XXX $instring;
    #close XXX;

    open OUT, "<testin/$out.out" or die "open: $!";
    my $outstring = join '', <OUT>;
    close OUT;

    is($broken, $outstring);
}    

1;

