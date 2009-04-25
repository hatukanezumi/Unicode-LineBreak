#-*- perl -*-

my @PROPS;
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
		$PROPS[$c] = $p;
	    }
	}
	#print STDERR "$start..$end\n";
    }
    close DATA;
}

#print STDERR "WRITE\n";

print <<EOF;
our \$$ARGV[2]_MAP = [
EOF

my $cat = $ARGV[2] || die;
my ($start, $end);
my ($c, $p);
for ($c = 0; $c <= $#PROPS; $c++) {
    unless ($PROPS[$c]) {
	next;
    } elsif (defined $end and $end + 1 == $c and $p eq $PROPS[$c]) {
	$end = $c;
    } else {
	if (defined $start and defined $end) {
	    printf "    [0x%04X, 0x%04X, '%s'],\n", $start, $end, $p;
	}

	$start = $end = $c;
	$p = $PROPS[$c];
    }
}
printf "    [0x%04X, 0x%04X, '%s'],\n", $start, $end, $p;
print <<EOF;
];

EOF
