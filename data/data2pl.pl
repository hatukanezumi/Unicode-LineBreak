#-*- perl -*-

my %PROPS;
my %PROP_EXCEPTIONS;

foreach my $n (1, 0) {
    open DATA, $ARGV[$n] || die $!;
    while (<DATA>) {
	chomp $_;
	s/\s*\#.*//;
	next unless /\S/;

	my ($char, $prop) = split /;/, $_;
	next unless $prop =~ /^\w+$/;
	my ($start, $end) = ();
	($start, $end) = split /\.\./, $char;
	$end ||= $start;
	foreach my $c (hex("0x$start") .. hex("0x$end")) {
	    if ($n) {
		$PROP_EXCEPTIONS{$c} = $prop;
	    } else {
		my $p = $PROP_EXCEPTIONS{$c} || $prop;
		$PROPS{$p} ||= [];
		push @{$PROPS{$p}}, $c;
	    }
	}
	#print STDERR "$start..$end\n";
    }
    close DATA;
}

#print STDERR "WRITE\n";

my $cat = $ARGV[2] || die;
foreach my $p (sort keys %PROPS) {
    print "sub ${cat}_$p {\n";
    print "    return <<'END';\n";
    my ($start, $end) = ();
    foreach my $c (sort {$a <=> $b} @{$PROPS{$p}}) {
	if (!defined $end) {
	    $start = $end = $c;
	} elsif ($end + 1 == $c) {
	    $end = $c;
	} else {
	    if ($start == $end) {
		printf "%04X\t\t\n", $start;
	    } else {
		printf "%04X\t%04X\t\n", $start, $end;
	    }
	    $start = $end = $c;
	}
    }
    if ($start == $end) {
	printf "%04X\t\t\n", $start;
    } else {
	printf "%04X\t%04X\t\n", $start, $end;
    }
    print "END\n";
    print "}\n";
    print "\n";
}

