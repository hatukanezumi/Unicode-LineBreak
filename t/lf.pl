use strict;
use Text::LineFold;

sub do5tests {
    my $in = shift;
    my $out = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = join '', <IN>;
    close IN;
    my $lf = Text::LineFold->new(@_);
    my %folded = ();
    foreach my $method (qw(PLAIN FIXED FLOWED)) {
	$folded{$method} = $lf->fold($instring, $method);
	open OUT, "<testin/$out.".(lc $method).".out" or die "open: $!";
	my $outstring = join '', <OUT>;
	close OUT;
	is($folded{$method}, $outstring);
    }
    foreach my $method (qw(FIXED FLOWED)) {
	my $outstring = $lf->unfold($folded{$method}, $method);
	is($outstring, $instring);
	#XXXopen XXX, ">testin/$out.".(lc $method).".xxx";
	#XXXprint XXX $outstring;
	#XXXclose XXX;
    }
}    

1;

