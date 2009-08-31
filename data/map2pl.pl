#-*- perl -*-

my $lang = shift @ARGV;

my $cat = $ARGV[2] || die;

my @PROPS = ();
my %CHARACTER_GROUP = ();
my %PROP_EXCEPTIONS = ();

# Read data
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
		# reduce trivial values.
		next if $cat eq 'lb' and $p =~ /^(AL|SG|XX)$/ or
			$cat eq 'ea' and $p eq 'N' or
			$cat eq 'script' and $p eq 'Unknown';
		# reduce ranges reserved for CJK ideographs.
		if (0x3400 <= $c and $c <= 0x4DBF or
		    0x4E00 <= $c and $c <= 0x9FFF or
		    0xF900 <= $c and $c <= 0xFAFF or
		    0x20000 <= $c and $c <= 0x2FFFD or
		    0x30000 <= $c and $c <= 0x3FFFD) {
		    if ($cat eq 'lb' and $p ne 'ID' or
			$cat eq 'ea' and $p ne 'W' or
			$cat eq 'script' and $p ne 'Unknown') {
			die sprintf 'U+%04X have %s proprty %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		# reduce private use areas.
		if (0xE000 <= $c and $c <= 0xF8FF or
		    0xF0000 <= $c and $c <= 0xFFFFD or
		    0x100000 <= $c and $c <= 0x10FFFD) {
		    if ($cat eq 'lb' and $p ne 'XX' or
			$cat eq 'ea' and $p ne 'A' or
			$cat eq 'script' and $p ne 'Unknown') {
			die sprintf 'U+%04X have %s proprty %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		# reduce Hangul syllables.
		if (0xAC00 <= $c and $c <= 0xD7A3) {
		    if ($cat eq 'lb' and ($c % 28 == 16 and $p ne 'H2' or
					  $c % 28 != 16 and $p ne 'H3') or
			$cat eq 'ea' and $p ne 'W' or
			$cat eq 'script' and $p ne 'Hangul') {
			die sprintf 'U+%04X have %s proprty %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		# reduce default ignorable code points.
		if ($cat eq 'ea'
		    and
		    (0x2060 <= $c and $c <= 0x206F or
		     0xFFF0 <= $c and $c <= 0xFFFB or
		     0xE0000 <= $c and $c <= 0xE0FFF)) {
		    if ($p ne 'Z') {
			die sprintf 'U+%04X have %s proprty %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		if ($cat eq 'lb'
		    and
		    (0xE0000 <= $c and $c <= 0xE0FFF)) {
		    if ($p ne 'CM') {
			die sprintf 'U+%04X have %s proprty %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		# reduce Yi syllables.
		if (0xA000 <= $c and $c <= 0xA48C and $c != 0xA015) {
		    if ($cat eq 'lb' and $p ne 'ID' or
			$cat eq 'ea' and $p ne 'W') {
			die sprintf 'U+%04X have %s proprty %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		$PROPS[$c] = $p;
	    }
	}
    }
    close DATA;
}

# Construct b-search table.
my ($beg, $end);
my ($c, $p);
my @MAP = ();
for ($c = 0; $c <= $#PROPS; $c++) {
    unless ($PROPS[$c]) {
	next;
    } elsif (defined $end and $end + 1 == $c and $p eq $PROPS[$c]) {
	$end = $c;
    } else {
	if (defined $beg and defined $end) {
	    push @MAP, [$beg, $end, $p];
	}
	$beg = $end = $c;
	$p = $PROPS[$c];
    }
}
push @MAP, [$beg, $end, $p];

# Print b-search table
if ($lang eq 'perl') {
    print "our \$${cat}_MAP = [\n";
} else {
    print "mapent_t linebreak_${cat}map[] = {\n";
}
if ($lang eq 'perl') {
    print join ",\n", map {
	my ($beg, $end, $p) = @{$_};
	sprintf "    [0x%04X, 0x%04X, %s_%s]", $beg, $end, uc($cat), $p;
    } @MAP;
} else {
    print join ",\n", map {
	my ($beg, $end, $p) = @{$_};
	sprintf "    {0x%04X, 0x%04X, %s_%s}", $beg, $end, uc($cat), $p;
    } @MAP;
}
if ($lang eq 'perl') {
    print "\n];\n\n";
} else {
    print "\n};\n\n";
    print "size_t linebreak_${cat}mapsiz = ".scalar(@MAP).";\n\n";
}

printf STDERR "======== Property %s ========\n%d characters, %d entries\n",
    uc $cat, scalar(grep $_, @PROPS), scalar(@MAP);

##########################################################################
exit 0 unless $cat eq 'lb' or $cat eq 'ea';

#Construct hash table.
my @HASH = ();
my @INDEX = ();
my $MODULUS = 1 << 11;
for (my $idx = 0; $idx <= $#MAP; $idx++) {
    my ($beg, $end, $p) = @{$MAP[$idx]};
    for (my $c = $beg; $c <= $end; $c++) {
	my $key = $c % $MODULUS;
	$HASH[$key] ||= [];
	unless (scalar @{$HASH[$key]} and
		$HASH[$key]->[$#{$HASH[$key]}] == $idx) {
	    push @{$HASH[$key]}, $idx;
	}
    }
}
my $HASHLEN = 0;
my $MAXBUCKETLEN = 0;
for (my $idx = 0; $idx < $MODULUS; $idx++) {
    my $len = scalar @{$HASH[$idx] || []};
    if ($len) {
	$INDEX[$idx] = $HASHLEN; # Index points start of bucket.
	$HASHLEN += $len;
    }
    if ($MAXBUCKETLEN <= $len) {
	#XXXprint STDERR join(' ',
	#XXX		  map { sprintf '[%04X..%04X %s]', @{$MAP[$_]} }
	#XXX		      @{$HASH[$idx] || []})."\n";
	$MAXBUCKETLEN = $len;
    }
}
$INDEX[$MODULUS] = $HASHLEN; # Sentinel.

# Print hash table index.
my $output = '';
my $line = '';
for (my $idx = 0; $idx < $MODULUS + 1; $idx++) {
    my $hidx = $INDEX[$idx];
    $hidx = $HASHLEN unless defined $hidx; # null index points out of table.
    if (76 < 4 + length($line) + length(", $hidx")) {
	$output .= ",\n" if length $output;
	$output .= "    $line";
	$line = '';
    }
    $line .= ", " if length $line;
    $line .= $hidx;
}
$output .= ",\n" if length $output;
$output .= "    $line";

if ($lang eq 'perl') {
} else {
    print "const unsigned short linebreak_${cat}hashidx[".$MODULUS." + 1] = {\n$output\n};\n\n";
}

# Print hash table.
my $output = '';
my $line = '';
for (my $idx = 0; $idx < $MODULUS; $idx++) {
    my @hidx = @{$HASH[$idx] || []};
    if (scalar @hidx) {
	foreach my $hidx (@hidx) {
	    if (76 < 4 + length($line) + length(", $hidx")) {
		$output .= ",\n" if length $output;
		$output .= "    $line";
		$line = '';
	    }
	    $line .= ", " if length $line;
	    $line .= $hidx;
	}
    }
}
$output .= ",\n" if length $output;
$output .= "    $line";

if ($lang eq 'perl') {
} else {
    print "const unsigned short linebreak_${cat}hash[".$HASHLEN."] = {\n$output\n};\n\n";
    print "size_t linebreak_${cat}hashsiz = $HASHLEN;\n\n";
}

my $idxld = scalar(grep {defined $_} @INDEX);
printf STDERR 'Index load: %d / %d = %0.1f%%'."\n",
    $idxld, $MODULUS, 100.0 * $idxld / $MODULUS;
printf STDERR 'Bucket size: total %d, max. %d, avg. %0.2f'."\n",
    $HASHLEN, $MAXBUCKETLEN, $HASHLEN / $idxld;

