package Unicode::LineBreak;

our @MAPs = ();

sub _loadmap {
    my $idx = shift;
    my $map = shift;
    $MAPs[$idx] = $map;
}

sub _loadrule { }

# _bsearch IDX, VAL
# Examine binary search on property map table with following structure:
# [
#     [start, stop, property_value],
#     ...
# ]
# where start and stop stands for a continuous range of UCS ordinal those
# are assigned property_value.
sub _bsearch {
    my $map = $MAPs[shift];
    my $val = shift;

    my $top = 0;
    my $bot = $#{$map};
    my $cur;

    while ($top <= $bot) {
        $cur = $top + int(($bot - $top) / 2);
        my $v = $map->[$cur];
        if ($val < $v->[0]) {
            $bot = $cur - 1;
        } elsif ($v->[1] < $val) {
            $top = $cur + 1;
        } else {
            return $v->[2];
        }
    }
    return undef;
}

sub _getlbrule {
    my $b_idx = shift;
    my $a_idx = shift;

    my $row;
    my $action;
    if (defined($row = $Unicode::LineBreak::RULES_MAP->[$b_idx]) and
        defined($action = $row->[$a_idx])) {
	return $action;
    }
    undef;
}

1;
