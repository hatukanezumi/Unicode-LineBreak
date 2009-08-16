#-*- perl -*-

require "lbclasses.pl";

my $cat = $ARGV[3] || die;
if ($cat eq 'lb') {
    @CLASSES = @LBCLASSES;
} elsif ($cat eq 'ea') {
    @CLASSES = @EAWIDTHS;
} elsif ($cat eq 'script') {
    @CLASSES = @SCRIPTS;
} else {
    @CLASSES = ();
}
%CLASSES = map { ($_ => 1) } @CLASSES;

my @PROPS = ();
my %CHARACTER_CLASS = ();
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
		    my $g = $1;
		    foreach my $p (split /:/, $g) {
			$CHARACTER_CLASS{$p} ||= [];
			push @{$CHARACTER_CLASS{$p}}, $c;
		    }
		    next;
		}
		$PROP_EXCEPTIONS{$c} = $prop;
	    } else {
		my $p = $PROP_EXCEPTIONS{$c} || $prop;
		$PROPS[$c] = $p;

		unless ($CLASSES{$p}) {
		    push @CLASSES, $p;
		    $CLASSES{$p} = 1;
		}
	    }
	}
	#print STDERR "$start..$end\n";
    }
    close DATA;
}

#print STDERR "WRITE\n";

print <<EOF;
our \$${cat}_MAP = [
EOF

my ($beg, $end);
my ($c, $p);
for ($c = 0; $c <= $#PROPS; $c++) {
    unless ($PROPS[$c]) {
	next;
    } elsif (defined $end and $end + 1 == $c and $p eq $PROPS[$c]) {
	$end = $c;
    } else {
	if (defined $beg and defined $end) {
	    printf "    [0x%04X, 0x%04X, %s_%s],\n", $beg, $end, uc($cat), $p;
	}
	$beg = $end = $c;
	$p = $PROPS[$c];
    }
}
printf "    [0x%04X, 0x%04X, %s_%s],\n", $beg, $end, uc($cat), $p;
print "];\n\n";

open CONSTANTS, ">", $ARGV[2] || die $!;
print CONSTANTS "use constant {\n";
my $i;
for ($i = 0; $i < scalar @CLASSES; $i++) {
    print CONSTANTS "    ".uc($cat)."_$CLASSES[$i] => $i,\n";
}
print CONSTANTS <<"EOF";
};

EOF

if (keys %CHARACTER_CLASS) {
    print CONSTANTS "use constant {\n";
    foreach my $class (sort keys %CHARACTER_CLASS) {
	print CONSTANTS "    ".uc($class)." => [";
	foreach my $c (sort {$a <=> $b} @{$CHARACTER_CLASS{$class}}) {
	    printf CONSTANTS "0x%04X, ", $c;
	}
	print CONSTANTS "],\n";
    }
    print CONSTANTS "};\n\n";
}
