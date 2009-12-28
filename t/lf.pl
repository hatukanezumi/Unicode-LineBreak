use strict;
use Text::LineFold;

sub dounfoldtest {
    my $in = shift;
    my $out = shift;
    my $method = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = join '', <IN>;
    close IN;
    my $lf = Text::LineFold->new(@_);
    my $unfolded = $lf->unfold($instring, $method);

    my $outstring = '';
    if (open OUT, "<testin/$out.out") {
        $outstring = join '', <OUT>;
        close OUT;
    } else {
        open XXX, ">testin/$out.xxx";
        print XXX $unfolded;
        close XXX;
    }

    is($unfolded, $outstring);
}

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
	my $outstring = '';
	if (open OUT, "<testin/$out.".(lc $method).".out") {
	    $outstring = join '', <OUT>;
	    close OUT;
	} else {
	    open XXX, ">testin/$out.".(lc $method).".xxx";
	    print XXX $folded{$method};
	    close XXX;
	}
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

sub dowraptest {
    my $in = shift;
    my $out = shift;

    open IN, "<testin/$in.in" or die "open: $!";
    my $instring = join '', <IN>;
    close IN;
    my $lf = Text::LineFold->new(@_);
    my $folded = $lf->fold("\t", ' ' x 4, $instring);

    my $outstring = '';
    if (open OUT, "<testin/$out.wrap.out") {
        $outstring = join '', <OUT>;
        close OUT;
    } else {
        open XXX, ">testin/$out.wrap.xxx";
        print XXX $folded;
        close XXX;
    }

    is($folded, $outstring);
}

1;

