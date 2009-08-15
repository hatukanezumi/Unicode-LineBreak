#-*- perl -*-

require "lbclasses.pl";

my $cat = $ARGV[3] || die;
my @CLASSES;
my $default;
my $id_prop;
my @MODULO = qw(20201 20219 20231 20233 20249 20261 20269 20287 20297);
my $RATE = 0.61803398875;

if ($cat eq 'lb') {
    @CLASSES = @LBCLASSES;
    $default = 'XX';
    $id_prop = 'ID';
    #XXX@MODULO = qw(30529 30539 30553 30557 30559);
} elsif ($cat eq 'ea') {
    @CLASSES = @EAWIDTHS;
    $default = 'N';
    $id_prop = 'W';
    #XXX@MODULO = qw(16619 16631 16633 16649 16651);
} elsif ($cat eq 'script') {
    @CLASSES = @SCRIPTS;
    $default = 'Unknown';
    $id_prop = 'Han';
    #XXX@MODULO = qw(593 599 601 607 613);
}
my %CLASSES = map { ($_ => 1) } @CLASSES;

my @PROPS = ();
my %CHARACTER_CLASS = ();
my %CHARACTER_GROUP = ();
my %PROP_EXCEPTIONS = ();
my @TBL = ();
my @IDX = ();

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
		next if $p eq $default;
		# Reserved for CJK Ideographs
		next if 0x3400 <= $c and $c <= 0x4DBF and $p eq $id_prop;
		next if 0x4E00 <= $c and $c <= 0x9FFF and $p eq $id_prop;
		next if 0xF900 <= $c and $c <= 0xFAFF and $p eq $id_prop;
		next if 0x20000 <= $c and $c <= 0x2FFFD and $p eq $id_prop;
		next if 0x30000 <= $c and $c <= 0x3FFFD and $p eq $id_prop;
		# Surrogates
		next if 0xD800 <= $c and $c <= 0xDFFF;
		# Private use
		next if 0xE000 <= $c and $c <= 0xF8FF;
		# Private planes
		next if 0xF0000 <= $c and $c <= 0xFFFFD;
		next if 0x100000 <= $c and $c <= 0x10FFFD;

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

my ($beg, $end);
my ($c, $p);
for ($c = 0; $c <= $#PROPS; $c++) {
    unless ($PROPS[$c]) {
	next;
    } elsif (defined $end and $end + 1 == $c and $p eq $PROPS[$c]) {
	$end = $c;
    } else {
	if (defined $beg and defined $end) {
	    push @TBL, [$beg, $end, $p];
	}
	$beg = $end = $c;
	$p = $PROPS[$c];
    }
}
push @TBL, [$beg, $end, $p];

print <<EOF;
our \$${cat}_MAP = [
EOF
foreach my $ent (@TBL) {
    my ($beg, $end, $p) = @$ent;
    printf "    [0x%04X, 0x%04X, %s_%s],\n", $beg, $end, uc($cat), $p;
}
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

my $mod;
my $count;
MODULO: while (1) {
    @IDX = ();
    print STDERR "COUNT = $count\n"; sleep 1;
    die unless scalar @MODULO;
    $mod = shift @MODULO;
    $count = 0;
    my $i;
    for ($i = 0; $i <= $#TBL; $i++) {
	my ($beg, $end, $prop) = @{$TBL[$i]};
	my $c;
	for ($c = $beg; $c <= $end; $c++) {
	    next MODULO unless &add_key($mod, $MODULO[0], $MODULO[1], 32767, $c, $i);
	    $count++;
	}
    }
    last;
}

print STDERR "COUNT = $count; MODULUS = $mod\n";
print 'our $'.$cat.'_IDX = [';
my $pos;
my $siz = 2**int(log($mod)/log(2)+1.5);
for ($pos = 0; $pos < $siz; $pos++) {
    my $ent = $IDX[$pos];
    if (defined $ent) {
	print "$ent->[1],";
    } else {
	print "undef,";
    }
    print "\n" if $pos % 10 == 9;
}
print "\n];\n\n";

sub add_key {
    my $mod = shift;
    my $mod2 = shift;
    my $mod3 = shift;
    my $siz = shift;
    my $key = shift; my $x = $key * $RATE; $x = int(($x - int($x)) * $siz);
    my $val = shift;
    my @alt = #(($key + 1) % $mod,
              # ($key >> 4 | ($key & 0x0F) << 16) % $mod,
              # ($key >> 8 | ($key & 0xFF) << 12) % $mod,
              # );
	      ((($key + 1) * $mod) & $siz,
	       (($key >> 8 | ($key & 0xFF) << 12) * $mod) & $siz,
	      #XXX #XXX(int($key+$mod3) * $mod3) & $siz,
	      #XXX);
	      #X($x,
	     );
    my $loop;
    for ($loop = 0; $loop < 256; $loop++) {
        my $pos;
        my @t = ();
        while (scalar @alt) {
            push @t, ($pos = shift @alt);
            unless (defined $IDX[$pos]) {
		printf STDERR "INSERT %04X => %d (%s)\n",
		       $key, $val, join(",", @alt, @t);
                $IDX[$pos] = [$key, $val, @alt, @t];
                return 1;
            }
        }
        @alt = @t;
        push @alt, ($pos = shift @alt);
        my ($k, $v, @a) = @{$IDX[$pos]};
	printf STDERR "KICKOUT %04X => %d => ", $key, $val, join(",", @alt);
        $IDX[$pos] = [$key, $val, @alt];
        ($key, $val, @alt) = ($k, $v, @a);
    }
    return 0;
}
