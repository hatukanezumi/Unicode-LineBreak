use strict;
use Unicode::LineBreak;

$Unicode::LineBreak::Config = {
    Detect7bit => 'YES',
    Mapping => 'EXTENDED',
    Replacement => 'DEFAULT',
    Breaking => 'DEFAULT',
    Charset => 'UTF-8',
    Context => '',
    HangulAsAL => 'NO',
    Language => 'XX',
    LegacyCM => "YES",
    MaxColumns => 76,
    Newline => "\n",
    NSKanaAsID => "NO",
    OutputCharset => 'UTF-8',
};

sub dotest {
    my $in = shift;
    my $out = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = join '', <IN>;
    close IN;
    my $lb = Unicode::LineBreak->new(@_);
    $instring = $lb->break($instring);
    #open XXX, ">testin/$out.xxx";
    #print XXX $instring;
    #close XXX;

    open OUT, "<testin/$out.out" or die "open: $!";
    my $outstring = join '', <OUT>;
    close OUT;

    is($instring, $outstring);
}    

1;

