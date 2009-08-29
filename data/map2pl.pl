#-*- perl -*-

my $lang = shift @ARGV;

my $cat = $ARGV[2] || die;

my @PROPS = ();
my %CHARACTER_GROUP = ();
my %PROP_EXCEPTIONS = ();

foreach my $n (1, 0) {
    next unless $ARGV[$n];
    open DATA, $ARGV[$n] || die $!;
    while (<DATA>) {
	chomp $_;
	s/\s*\#.*//;
	next unless /\S/;

	my ($char, $prop) = split /\s*;\s*/, $_;
	next unless $prop =~ /^(\@[\w:]+|\w+)$/;
	my ($start, $end) = ();
	($start, $end) = split /\.\./, $char;
	$end ||= $start;
	foreach my $c (hex("0x$start") .. hex("0x$end")) {
	    if ($n) {
		if ($prop =~ /^\@([\w:]+)/) {
		    next;
		}
		$PROP_EXCEPTIONS{$c} = $prop;
	    } else {
		my $p = $PROP_EXCEPTIONS{$c} || $prop;
		next if $cat eq 'lb' and $p =~ /^(AL|SG|XX)$/ or
			$cat eq 'ea' and $p eq 'N' or
			$cat eq 'script' and $p eq 'Common';
		$PROPS[$c] = $p;
	    }
	}
	#print STDERR "$start..$end\n";
    }
    close DATA;
}

#print STDERR "WRITE\n";


if ($lang eq 'perl') {
    print "our \$${cat}_MAP = [\n";
} else {
    print "mapent_t linebreak_${cat}map[] = {\n";
}

my ($beg, $end);
my ($c, $p, $siz);
for ($c = 0; $c <= $#PROPS; $c++) {
    unless ($PROPS[$c]) {
	next;
    } elsif (defined $end and $end + 1 == $c and $p eq $PROPS[$c]) {
	$end = $c;
    } else {
	if (defined $beg and defined $end) {
	    if ($lang eq 'perl') {
		printf "    [0x%04X, 0x%04X, %s_%s],\n", $beg, $end, uc($cat), $p;
	    } else {
		printf "    {0x%04X, 0x%04X, %s_%s},\n", $beg, $end, uc($cat), $p;
		$siz++;
	    }
	}
	$beg = $end = $c;
	$p = $PROPS[$c];
    }
}
if ($lang eq 'perl') {
    printf "    [0x%04X, 0x%04X, %s_%s],\n", $beg, $end, uc($cat), $p;
    print "];\n\n";
} else {
    printf "    {0x%04X, 0x%04X, %s_%s},\n", $beg, $end, uc($cat), $p;
    $siz++;
    print "    {0, 0, PROP_UNKNOWN}\n";
    print "};\n\n";
    print "size_t linebreak_${cat}mapsiz = $siz;\n\n";
}

