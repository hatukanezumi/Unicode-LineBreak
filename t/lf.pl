use strict;
use Text::LineFold;

sub dotest {
    my $in = shift;
    my $out = shift;
    my $method = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = join '', <IN>;
    close IN;
    my $lf = Text::LineFold->new(@_);
    my $folded = $lf->fold($instring, $method);
    #open XXX, ">testin/$out.xxx";
    #print XXX $folded;
    #close XXX;

    open OUT, "<testin/$out.out" or die "open: $!";
    my $outstring = join '', <OUT>;
    close OUT;

    is($folded, $outstring);
}    

1;

