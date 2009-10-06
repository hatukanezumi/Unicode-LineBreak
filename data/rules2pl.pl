#! perl

use constant MANDATORY => 3;
use constant DIRECT_ALLOWED => 2;
use constant DIRECT_PROHIBITED => -1;
use constant INDIRECT_PROHIBITED => -2;

my $version = $ARGV[1];

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

my @rows = ();
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
    push @rows, [$b, [@actions]];
}

open DATA_PM, '>>', "../lib/Unicode/LineBreak/$version.pm" || $!;
open DATA_C, '>>', "../linebreak/lib/$version.c" || $!;

print DATA_PM "# Note: Entries related to BK, CR, CM, LF, NL, SP aren't used by break().\n";
print DATA_PM "our \$RULES = [\n";
print DATA_PM "  #";
foreach my $c (@LBCLASSES) { $c =~ /(.)(.)/; print DATA_PM $1.lc($2) }
print DATA_PM "\n";
print DATA_PM join "\n", map {
    my $b = $_->[0];
    my @actions = @{$_->[1]};
    "  [" . join(',',@actions) . "], #$b";
} @rows;
print DATA_PM "\n];\n\n";

print DATA_C "/* Note: Entries related to BK, CR, CM, LF, NL, SP aren't used by break(). */\n";
print DATA_C "propval_t linebreak_rules[".(scalar @LBCLASSES)."][".(scalar @LBCLASSES)."] = {\n";
print DATA_C "     /*";
foreach my $c (@LBCLASSES) { $c =~ /(.)(.)/; print DATA_C $1.lc($2) }
print DATA_C "*/\n";
print DATA_C join ",\n", map {
    my $b = $_->[0];
    my @actions = @{$_->[1]};
    "/*$b*/{" . join(',',@actions) . "}";
} @rows;
print DATA_C "\n};\n\n";
print DATA_C "size_t linebreak_rulessiz = ".scalar(@LBCLASSES).";\n\n";
