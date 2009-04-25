use strict;
use Unicode::LineBreak;

$Unicode::LineBreak::Config = {
    Detect7bit => 'YES',
    Mapping => 'EXTENDED',
    Replacement => 'DEFAULT',
    Charset => 'UTF-8',
    HangulAsAL => 'NO',
    OutputCharset => 'UTF-8',
    Break => "\n",
    MaxColumns => 76,
};

sub dotest {
    my $in = shift;
    my $out = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = join '', <IN>;
    close IN;
    my $lb = Unicode::LineBreak->new($instring, @_);
    $instring = $lb->break();
    #open XXX, ">testin/$out.xxx";
    #print XXX $instring;
    #close XXX;

    open OUT, "<testin/$out.out" or die "open: $!";
    my $outstring = join '', <OUT>;
    close OUT;

    is($instring, $outstring);
}    

1;

