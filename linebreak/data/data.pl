#! perl

my @cat = split(',', shift @ARGV) or die;
my $version = shift @ARGV or die;

my %SA = ();
foreach my $ext ('custom', 'txt') {
    open LB, '<', "LineBreak-$version.$ext" or next;
    while (<LB>) {
	chomp $_;
	s/\s*#.*$//;
	next unless /\S/;
	my ($code, $prop) = split /;/;
	$code = hex("0x$code");
	$SA{$code} = 1 if $prop eq 'SA';
    }
    close LB;
}

### Build rule map.

use constant MANDATORY => 3;
use constant DIRECT_ALLOWED => 2;
use constant DIRECT_PROHIBITED => -1;
use constant INDIRECT_PROHIBITED => -2;

require "LBCLASSES";
my @LBCLASSES = @{$indexedclasses{'lb'}->{$version}};

my %ACTIONS = ('!' => MANDATORY,
	       'SP*×' => INDIRECT_PROHIBITED,
               '×' => DIRECT_PROHIBITED,
               '÷' => DIRECT_ALLOWED,
    );

open RULES, "<", "Rules-$version.txt" or die $!;

my @rules = ();
while (<RULES>) {
    chomp $_;
    s/^\s+//;
    if (!/\S/ or /^\#/) {
        next;
    } elsif (/Assign a line breaking class/) {
        next;
    } elsif (/Treat X CM\* as if it were X/) {
        next;
    } elsif (/Treat any remaining CM as i. i. were AL/) {
        next;
    }

    my ($left, $break, $right) = split(/\s*(!|SP\*\s*×|×|÷)\s*/, $_);
    $left = &class2re($left);
    $right = &class2re($right);
    $break =~ s/\s+//g;
    $break = $ACTIONS{$break};

    push @rules, [$left, $break, $right];
}

sub class2re {
    my $class = shift;

    if ($class =~ /\(([^)]+)\)/) {
	$class = &inclusive2re($1);
    } elsif ($class =~ /[[]\^([^]]+)\]/) {
	$class = &exclusive2re($1);
    } elsif ($class =~ /(\S+)/) {
	if ($& eq 'ALL') {
	    $class = qr{.+};
	} else {
	    $class = qr{$&};
	}
    } else {
	$class = qr{.+};
    }
    return $class;
}

sub inclusive2re {
    my $class = shift;
    $class =~ s/^\s+//; $class =~ s/\s+$//;
    $class = join '|', split /\s*\|\s*/, $class;
    return qr{$class};
}

sub exclusive2re {
    my $class = shift;
    $class =~ s/^\s+//; $class =~ s/\s+$//;
    my @class = split /\s*\|\s*/, $class;
    my %class;

    foreach my $c (@class) {
        $class{$c} = 1;
    }
    @class = ();
    foreach my $c (@LBCLASSES) {
        push @class, $c unless $class{$c};
    }
    $class = join('|', @class);
    return qr{$class};
}

my @RULES = ();
foreach my $b (@LBCLASSES) {
    my @actions = ();
    foreach my $a (@LBCLASSES) {
	my $direct = undef;
	my $indirect = undef;
	my $mandatory = undef;
	foreach my $r (@rules) {
	    my ($before, $action, $after) = @{$r};
	    if ($b =~ /$before/ and $a =~ /$after/) {
		if ($action == MANDATORY) {
		    $mandatory = 1;
		    $direct = 1 unless defined $direct;
		} elsif ($action == INDIRECT_PROHIBITED) {
		    $direct = 0 unless defined $direct;
		    $indirect = 0 unless defined $indirect;
		} elsif ($action == DIRECT_PROHIBITED) {
		    $direct = 0 unless defined $direct;
		} elsif ($action == DIRECT_ALLOWED) {
		    $direct = 1 unless defined $direct;
		}
	    }

	    if ("SP" =~ /$before/ and $a =~ /$after/) {
		if ($action == DIRECT_ALLOWED) {
		    $indirect = 1 unless defined $indirect;
		} elsif ($action == DIRECT_PROHIBITED or
			 $action == INDIRECT_PROHIBITED) {
		    $indirect = 0 unless defined $indirect;
		}
	    }

	    last if defined $direct and defined $indirect;
	}
	my $action;
	if ($mandatory and $direct) {
	    $action = 'M'; # '!'
	} elsif ($direct) {
	    $action = 'D'; # '_'
	} elsif ($indirect) {
	    $action = 'I'; # '%'
	} else {
	    $action = 'P'; # '^'
	}

	push @actions, $action;
    }
    push @RULES, [$b, [@actions]];
}

### Build property map

my @PROPS = ();
foreach my $cat (@cat) {

my %PROP_EXCEPTIONS = ();

# Read data
my $data;
if ($cat eq 'lb') {
    $data = 'LineBreak';
} elsif ($cat eq 'ea') {
    $data = 'EastAsianWidth';
} elsif ($cat eq 'gb') {
    $data = 'GraphemeBreakProperty';
} elsif ($cat eq 'sc') {
    $data = 'Scripts';
} else {
    die "Unknown property $cat";
}
my @data = ("$data-$version.txt");
push @data, "$data-$version.custom" if -e "$data-$version.custom";
foreach my $n (1, 0) {
    next unless $data[$n];
    open DATA, '<', $data[$n] or die $!;
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
		# reduce ranges reserved for CJK ideographs.
		if (0x3400 <= $c and $c <= 0x4DBF or
		    0x4E00 <= $c and $c <= 0x9FFF or
		    0xF900 <= $c and $c <= 0xFAFF or
		    0x20000 <= $c and $c <= 0x2FFFD or
		    0x30000 <= $c and $c <= 0x3FFFD) {
		    if ($cat eq 'lb' and $p ne 'ID' or
			$cat eq 'ea' and $p ne 'W' or
			$cat eq 'gb' and $p ne 'Other' or
			$cat eq 'sc' and $p ne 'Han') {
			die sprintf 'U+%04X have %s property %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		# reduce private use areas.
		elsif (0xE000 <= $c and $c <= 0xF8FF or
		    0xF0000 <= $c and $c <= 0xFFFFD or
		    0x100000 <= $c and $c <= 0x10FFFD) {
		    if ($cat eq 'lb' and $p ne 'XX' or
			$cat eq 'ea' and $p ne 'A' or
			$cat eq 'gb' and $p ne 'Other' or
			$cat eq 'sc' and $p ne 'Unknown') {
			die sprintf 'U+%04X have %s property %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		# check plane 14.
		elsif ($c == 0xE0001 or 0xE0020 <= $c and $c <= 0xE007F) {
		    if ($cat eq 'lb' and $p ne 'CM' or
			$cat eq 'ea' and $p ne 'Z' or
			$cat eq 'gb' and $p ne 'Control' or
			$cat eq 'sc' and $p ne 'Common') {
			die sprintf 'U+%04X have %s property %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		elsif (0xE0100 <= $c and $c <= 0xE01EF) {
		    if ($cat eq 'lb' and $p ne 'CM' or
			$cat eq 'ea' and $p ne 'Z' or
			$cat eq 'gb' and $p ne 'Extend' or
			$cat eq 'sc' and $p ne 'Inherited') {
			die sprintf 'U+%04X have %s property %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		# check unallocated high planes.
		elsif (0x20000 <= $c) {
		    if ($cat eq 'lb' and $p ne 'XX' or
			$cat eq 'ea' and $p ne 'N' or
			$cat eq 'gb' and $p ne 'Other' or
			$cat eq 'sc' and $p ne 'Unknown') {
			die sprintf 'U+%04X have %s property %s', $c, $cat, $p;
		    } else {
			next;
		    }
		}
		$PROPS[$c] ||= {};
		$PROPS[$c]->{$cat} = $p;
	    }
	}
    }
    close DATA;
}

} # foreach my $cat

for (my $c = 0; $c <= $#PROPS; $c++) {
    next unless $PROPS[$c];

    # limit scripts to SA characters.
    delete $PROPS[$c]->{'sc'} if !$SA{$c};

    # reduce trivial values.
    delete $PROPS[$c]->{'lb'} if $PROPS[$c]->{'lb'} =~ /^(AL|SG|XX)$/;
    #delete $PROPS[$c]->{'ea'} if $PROPS[$c]->{'ea'} eq 'N';
    #delete $PROPS[$c]->{'gb'} if $PROPS[$c]->{'gb'} eq 'Other';
    #delete $PROPS[$c]->{'sc'} if $PROPS[$c]->{'sc'} eq 'Unknown';

    unless (scalar keys %{$PROPS[$c]}) {
	delete $PROPS[$c];
	next;
    } else {
	$PROPS[$c]->{'gb'} = 'Other' unless $PROPS[$c]->{'gb'};
    }

    # Check exceptions
    if ($PROPS[$c]->{'gb'} =~ /Extend|SpacingMark/ and
	$PROPS[$c]->{'lb'} !~ /CM|SA/ or
	$PROPS[$c]->{'gb'} eq 'Prepend' and
	$PROPS[$c]->{'lb'} !~ /AL|SA/
	) {
	warn sprintf '!CM:U+%04X: lb => %s, ea => %s, gb => %s, sc => %s'."\n",
	$c,
	$PROPS[$c]->{'lb'} || '-',
	$PROPS[$c]->{'ea'} || '-',
	$PROPS[$c]->{'gb'} || '-',
	$PROPS[$c]->{'sc'} || '-';
    }

    # Check exceptions
    if ($PROPS[$c]->{'gb'} ne 'Control' and
	$PROPS[$c]->{'lb'} =~ /ZW|WJ|BK|NL/) {
	warn sprintf '!Control:U+%04X: lb => %s, ea => %s, gb => %s, sc => %s'."\n",
	$c,
	$PROPS[$c]->{'lb'} || '-',
	$PROPS[$c]->{'ea'} || '-',
	$PROPS[$c]->{'gb'} || '-',
	$PROPS[$c]->{'sc'} || '-';
    }

=begin comment

    if ($PROPS[$c]->{'gb'} !~ /Extend|SpacingMark/ and
	$PROPS[$c]->{'lb'} eq 'CM') {
	warn sprintf 'CM: U+%04X: lb => %s, ea => %s, gb => %s, sc => %s'."\n",
	$c,
	$PROPS[$c]->{'lb'} || '-',
	$PROPS[$c]->{'ea'} || '-',
	$PROPS[$c]->{'gb'} || '-',
	$PROPS[$c]->{'sc'} || '-';
    }

=cut

}


# Construct compact array.
use constant BLKLEN => 1 << 5;
my @C_ARY = ();
my @C_IDX = ();
for (my $idx = 0; $idx < 0x20000; $idx += BLKLEN) {
    my @BLK = ();
    for (my $bi = 0; $bi < BLKLEN; $bi++) {
	my $c = $idx + $bi;
	my %blk = ();
	# ranges reserved for CJK ideographs.
	if (0x3400 <= $c and $c <= 0x4DBF or
	    0x4E00 <= $c and $c <= 0x9FFF or
	    0xF900 <= $c and $c <= 0xFAFF or
	    0x20000 <= $c and $c <= 0x2FFFD or
	    0x30000 <= $c and $c <= 0x3FFFD) {
	    %blk = ('lb' => 'ID', 'ea' => 'W', 'sc' => 'Han');
	# ranges reserved for private use.
	} elsif (0xE000 <= $c and $c <= 0xF8FF or
		 0xF0000 <= $c and $c <= 0xFFFFD or
		 0x100000 <= $c and $c <= 0x10FFFD) {
	    %blk = ('ea' => 'A');
	} elsif ($PROPS[$c]) {
	    foreach my $prop (@cat) {
		$blk{$prop} = $PROPS[$c]->{$prop};
	    }
	}
	$blk{'lb'} ||= 'AL';
	$blk{'ea'} ||= 'N';
	$blk{'gb'} ||= 'Other';
	$blk{'sc'} ||= 'Unknown';

	$BLK[$bi] = \%blk;
    }
    my ($ci, $bi);
    C_ARY: for ($ci = 0; $ci <= $#C_ARY; $ci++) {
	for ($bi = 0; $bi < BLKLEN; $bi++) {
	    last C_ARY if $#C_ARY < $ci + $bi;
	    last unless &hasheq($BLK[$bi], $C_ARY[$ci + $bi]);
	} 
	last C_ARY if $bi == BLKLEN;
    }
    push @C_IDX, $ci;
    if ($bi < BLKLEN) {
	for ( ; $bi < BLKLEN; $bi++) {
	    push @C_ARY, $BLK[$bi];
	}
    }
    #printf STDERR "U+%04X..U+%04X: %d..%d / %d      \r", $idx, $idx + (BLKLEN) - 1, $ci, $ci + (BLKLEN) - 1, scalar @C_ARY;
}
#print STDERR "\n";

### Output

open DATA_C, '>', "../lib/$version.c" or die $!;

# Print postamble.
print DATA_C <<"EOF";
/*
 * This file is automatically generated.  DON'T EDIT THIS FILE MANUALLY.
 */

#include "linebreak_defs.h"
#define UNICODE_VERSION "$version"
const char *linebreak_unicode_version = UNICODE_VERSION;

EOF

# Print property values.
foreach my $k (sort keys %indexedclasses) {
    my $output = '';
    my $line = '    ';
    my @propvals = @{$indexedclasses{$k}->{$version}};
    push @propvals, qw(SG AI SA XX)
	if uc($k) eq 'LB';
    foreach my $v (@propvals) {
	if (76 < 4 + length($line) + length($v)) {
	    $output .= "$line\n";
	    $line = '    ';
	}
	$line .= "\"$v\", ";
    }
    $line .= "\n    "
	if 76 < length($line) + 4;
    $output .= "${line}NULL";
    print DATA_C "const char *linebreak_propvals_".uc($k)."[] = {\n";
    print DATA_C "$output\n";
    print DATA_C "};\n";
}
print DATA_C "\n";

# print rule map.
my $clss = join '', map { /(.)(.)/; $1.lc($2); } @LBCLASSES;
print DATA_C <<"EOF";
#define r(cc) static propval_t rule_##cc[]
/* Note: Entries related to BK, CR, CM, LF, NL, SP aren't used by break(). */
    /* $clss */
EOF
print DATA_C join "\n", map {
    my $b = $_->[0];
    my @actions = @{$_->[1]};
    "r(" . $_->[0] . ")={" . join(',',@actions) . "};";
} @RULES;
print DATA_C "\n";
print DATA_C "#undef r\n";
print DATA_C "propval_t *linebreak_rules[] = {";
for (my $i = 0; $i <= $#LBCLASSES; $i++) {
    print DATA_C ", " if $i;
    print DATA_C "\n    " if $i % 8 == 0;
    print DATA_C "rule_$LBCLASSES[$i]";
}
print DATA_C "\n};\n\n";
print DATA_C "size_t linebreak_rulessiz = ".scalar(@LBCLASSES).";\n\n";

# print compact array index.
my $output = '';
my $line = '';
print DATA_C "unsigned short linebreak_prop_index[] = {\n";
foreach my $ci (@C_IDX) {
    if (76 < 4 + length($line) + length(", $ci")) {
	$output .= ",\n" if length $output;
	$output .= "    $line";
	$line = '';
    }
    $line .= ", " if length $line;
    $line .= "$ci";
}
$output .= ",\n" if length $output;
$output .= "    $line";
print DATA_C "$output\n};\n\n";

# print compact array.
$output = '';
$line = '';
print DATA_C "propval_t linebreak_prop_array[] = {\n";
foreach my $b (@C_ARY) {
    foreach my $prop (@cat) {
	my $citem;
	unless ($b->{$prop}) {
	    die "$prop property unknown\n" unless $prop eq 'sc';
	    $citem = 'PROP_UNKNOWN';
	} else {
	    $citem = uc($prop) . '_' . $b->{$prop};
	}
	if (76 < 4 + length($line) + length(", $citem")) {
	    $output .= ",\n" if length $output;
	    $output .= "    $line";
 	    $line = '';
        }
	$line .= ", " if length $line;
	$line .= $citem;
    }
}
$output .= ",\n" if length $output;
$output .= "    $line";
print DATA_C "$output\n};\n\n";

### Print postamble

### Statistics.
my $idxld = scalar(grep {defined $_} @INDEX) - 1;
printf STDERR "======== Version %s ========\n%d characters (in BMP and SMP), %d entries\n",
    $version, scalar(grep $_, @PROPS) +
    0x4DBF - 0x3400 + 1 + 0x9FFF - 0x4E00 + 1 + 0xFAFF - 0xF900 + 1 +
    0xF8FF - 0xE000 + 1, scalar(@C_ARY);

############################################################################

sub hasheq {
    my $a = shift;
    my $b = shift;
    foreach my $cat (@cat) {
	if (!defined $a->{$cat} and !defined $b->{$cat}) {
	    next;
	} elsif (!defined $a->{$cat} or !defined $b->{$cat}) {
	    return 0;
	} elsif ($a->{$cat} ne $b->{$cat}) {
	    return 0;
	}
    }
    return 1;
}

