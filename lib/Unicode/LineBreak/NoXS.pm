package Unicode::LineBreak;

sub _loadconst { }
our @MAPs = ();
sub _loadmap {
    my $idx = shift;
    my $map = shift;
    $MAPs[$idx] = $map;
}
sub _loadrule { }
sub _packed_hash { return {@_}; }

# _bsearch IDX, VAL, DEFAULT, HASH
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
    my $def = shift;
    my $res = shift;

    my $top = 0;
    my $bot = $#{$map};
    my $cur;
    my $result;

    while ($top <= $bot) {
        $cur = $top + int(($bot - $top) / 2);
        my $v = $map->[$cur];
        if ($val < $v->[0]) {
            $bot = $cur - 1;
        } elsif ($v->[1] < $val) {
            $top = $cur + 1;
        } else {
            $result = $v->[2];
	    last;
        }
    }
    $result = $def unless defined $result;
    my $r = $res->{$result};
    $result = $r if defined $r;
    $result;
}

sub getlbclass {
    my $self = shift;
    my $str = shift;
    return undef unless defined $str and length $str;
    &_bsearch(0, ord($str), LB_XX, $self->{_lb_hash});
}

sub getlbrule {
    my $self = shift;
    my $b_idx = shift;
    my $a_idx = shift;
    return undef unless defined $b_idx and defined $a_idx;

    my $row;
    my $action;
    my $result = undef;
    if (defined($row = $Unicode::LineBreak::RULES_MAP->[$b_idx]) and
        defined($action = $row->[$a_idx])) {
	$result = $action;
    }
    $result = DIRECT unless defined $result;
    my $r = $res->{$result};
    $result = $r if defined $r;
    $result;
}

1;
