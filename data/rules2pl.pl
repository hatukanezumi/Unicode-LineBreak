#! perl

my @CLASSES = qw{OP CL QU GL NS EX SY IS PR PO NU AL ID IN HY BA BB B2 ZW CM WJ H2 H3 JL JV JT};
my %ACTIONS = ('!' => 'MANDATORY',
	       '×' => 'NO_BREAK',
	       '÷' => 'ALLOWED',
    );
my $OMIT_CM = 0;
my $CM_AS_AL = 0;

print <<'EOF';
#-*- perl -*-

package Unicode::LineBreak;

sub _breakable {
    my $s = shift;
    my $str = $s->{_str};
    pos($str) = $s->{_pos};

    return (EOT, '') unless $str;

EOF

open RULES, "<", $ARGV[0] || die;
while (<RULES>) {
    chomp $_;
    s/^¥s+//;
    if (!/\S/ or /^\#/) {
	print "$_\n";
	next;
    } elsif (/Assign a line breaking class/) {
        print "    # $_\n";
        next;
    } elsif (/Treat X CM\* as if it were X/) {
	$OMIT_CM = 1;
        print "    # $_\n";
        next;
    } elsif (/Treat any remaining CM as i. i. were AL/) {
        $CM_AS_AL = 1;
        print "    # $_\n";
        next;
    } else {
	print "    # $_\n";
    }

    my ($left, $break, $right) = split(/\s*(!|×|÷)\s*/, $_);
    $left = &class2re($left, 0);
    $right = &class2re($right, 1);
    $break = $ACTIONS{$break};

    next if $left =~ /\\A/;
    $break = 'EOT' if $right =~ /\\z/;

    print <<"EOF";
    if (\$str =~ m/\\G$left(?=$right)/cgsx) {
	\$s->{_pos} = pos(\$str);
	return ($break, \$&);
    }
EOF
}
close RULES;

print <<'EOF';

    return NO_BREAK;
}

1;
EOF

sub class2re {
    my $class = shift;
    my $is_right = shift;

    $class =~ s/\(([^)]+)\)/&inclusive2re($1)/eg;
    $class =~ s/[[]\^([^]]+)\]/&exclusive2re($1)/eg;
    $class =~ s/\b(sot|eot|[A-Z][0-9A-Z]|ALL)\b/&atom2re($1,$is_right)/eg;
    $class = '.' unless $class =~ /\S/;
    return $class;
}

sub inclusive2re {
    my $class = shift;
    $class =~ s/^\s+//; $class =~ s/\s+$//;
    $class = join '|', split /\s*\|\s*/, $class;
    return "(?:$class)";
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
    foreach my $c (@CLASSES) {
	push @class, $c unless $class{$c};
    }
    $class = join('|', @class);
    return "(?:$class)";
}

sub atom2re {
    my $atom = shift;
    my $is_right = shift;

    if ($atom eq 'sot') {
	$atom = '\\A';
    } elsif ($atom eq 'eot') {
	$atom = '\\z';
    } elsif ($atom eq 'ALL') {
	$atom = '.';
    } elsif ($CM_AS_AL and $atom eq 'AL' and not $is_right) {
        $atom = '(?:$s->{lb_AL}|$s->{lb_CM})';
	$atom .= '$s->{lb_CM}*' if $OMIT_CM;
    } elsif ($OMIT_CM and $atom !~ /BK|CR|LF|NL|SP|ZW/ and not $is_right) {
	$atom = '$s->{lb_'.$atom.'}$s->{lb_CM}*';
    } else {
        $atom = '$s->{lb_'.$atom.'}';
    }

    return $atom;
}

