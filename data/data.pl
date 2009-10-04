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

open RULES, "<", "Rules-$version.txt" || die;

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
    open DATA, '<', $data[$n] || die $!;
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
			$cat eq 'gb' and $p ne 'Other' or
			$cat eq 'sc' and $p ne 'Unknown') {
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
			$cat eq 'gb' and ($c % 28 == 16 and $p ne 'LV' or
                                          $c % 28 != 16 and $p ne 'LVT') or
			$cat eq 'sc' and $p ne 'Hangul') {
			die sprintf 'U+%04X have %s proprty %s', $c, $cat, $p;
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
    my $props = $PROPS[$c];
    next unless $props;

    # limit scripts to SA characters.
    delete $props->{'sc'} if !$SA{$c};

    my %props = (%{$props});

    # reduce trivial values.
    delete $props{'lb'} if $props{'lb'} =~ /^(AL|SG|XX)$/;
    delete $props{'ea'} if $props{'ea'} eq 'N';
    delete $props{'gb'} if $props{'gb'} eq 'Other';
    delete $props{'sc'} if $props{'sc'} eq 'Unknown';

    unless (scalar keys %props) {
	delete $PROPS[$c];
	next;
    } else {
	$PROPS[$c]->{'gb'} = 'Other' unless $PROPS[$c]->{'gb'};
    }

    # Check exceptions
    if ($PROPS[$c]->{'gb'} =~ /Extend|SpacingMark/ and
	$PROPS[$c]->{'lb'} !~ /CM|SA/ or
	#XXX$PROPS[$c]->{'gb'} !~ /Extend|SpacingMark/ and
	#XXX$PROPS[$c]->{'lb'} eq 'CM' or
	$PROPS[$c]->{'gb'} eq 'Prepend' and
	$PROPS[$c]->{'lb'} !~ /AL|SA/
	) {
	warn sprintf 'U+%04X: lb => %s, ea => %s, gb => %s, sc => %s'."\n",
	$c,
	$PROPS[$c]->{'lb'} || '-',
	$PROPS[$c]->{'ea'} || '-',
	$PROPS[$c]->{'gb'} || '-',
	$PROPS[$c]->{'sc'} || '-';
    }
}


# Construct b-search table.
my ($beg, $end);
my ($c, $p);
my @MAP = ();
for ($c = 0; $c <= $#PROPS; $c++) {
    unless ($PROPS[$c]) {
	next;
    } elsif (defined $end and $end + 1 == $c and &hasheq($p, $PROPS[$c])) {
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

#Construct hash table.
my @HASH = ();
my @INDEX = ();
my $MODULUS = 1 << 13;
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

### Output

open DATA_C, '>', "../linebreak/$version.c";

# Print postamble.
print DATA_C <<"EOF";
/*
 * This file is automatically generated.  DON'T EDIT THIS FILE MANUALLY.
 */

#include "linebreak.h"
#define UNICODE_VERSION "$version"
const char *linebreak_unicode_version = UNICODE_VERSION;

EOF

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

# Print b-search table
$output = join ",\n", map {
    my ($beg, $end, $p) = @{$_};
    my $props = join ', ',
    map {$p->{$_}? uc($_).'_'.$p->{$_}: 'PROP_UNKNOWN'} @cat;
    sprintf "    {0x%04X, 0x%04X, %s}", $beg, $end, $props;
} @MAP;
print DATA_C "mapent_t linebreak_map[] = {\n$output\n};\n\n";

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

print DATA_C <<"EOF";
const unsigned short linebreak_index\[$MODULUS + 1\] = {
$output
};

EOF

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

print DATA_C <<"EOF";
const unsigned short linebreak_hash\[$HASHLEN\] = {
$output
};

size_t linebreak_hashsiz = $HASHLEN;

EOF

### Print postamble

### Statistics.
my $idxld = scalar(grep {defined $_} @INDEX) - 1;
printf STDERR "======== Version %s ========\n%d characters, %d entries\n",
    $version, scalar(grep $_, @PROPS), scalar(@MAP);
printf STDERR 'Index load: %d / %d = %0.1f%%'."\n",
    $idxld, $MODULUS, 100.0 * $idxld / $MODULUS;
printf STDERR 'Bucket size: total %d, max. %d, avg. %0.2f'."\n",
    $HASHLEN, $MAXBUCKETLEN, $HASHLEN / $idxld;

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

