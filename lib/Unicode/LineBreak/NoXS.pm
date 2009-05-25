package Unicode::LineBreak;

sub _loadconst { }
our @MAPs = ();
sub _loadmap ($$) {
    my $idx = shift;
    my $map = shift;
    $MAPs[$idx] = $map;
}
sub _loadrule { }
sub _packed_table (@) { return {@_}; }

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

sub eawidth ($$) {
    my $self = shift;
    my $str = shift;
    return undef unless defined $str and length $str;
    &_bsearch(1, ord($str), EA_A, $self->{_ea_hash});
}

sub lbclass ($$) {
    my $self = shift;
    my $str = shift;
    return undef unless defined $str and length $str;
    &_bsearch(0, ord($str), LB_XX, $self->{_lb_hash});
}

sub lbrule ($$$) {
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

sub strsize ($$$$$;$) {
    my $self = shift;
    my $len = shift;
    my $pre = shift;
    my $spc = shift;
    my $str = shift;
    my $max = shift || 0;
    $spc = '' unless defined $spc;
    $str = '' unless defined $str;
    return $max? 0: $len
	unless length $spc or length $str;

    my $spcstr = $spc.$str;
    my $length = length $spcstr;
    my $idx = 0;
    my $pos = 0;
    while (1) {
	my ($clen, $c, $cls, $nc, $ncls, $width, $w);

	if ($length <= $pos) {
	    last;
	}
	$c = substr($spcstr, $pos, 1);
	$cls = $self->lbclass($c);
	$clen = 1;

	# Hangul syllable block
	if ($cls == LB_H2 or $cls == LB_H3 or
	    $cls == LB_JL or $cls == LB_JV or $cls == LB_JT) {
	    while (1) {
		$pos++;
		last if $length <= $pos;
		$nc = substr($spcstr, $pos, 1);
		$ncls = $self->lbclass($nc);
		if (($ncls == LB_H2 or $ncls == LB_H3 or
		    $ncls == LB_JL or $ncls == LB_JV or $ncls == LB_JT) and
		    $self->lbrule($cls, $ncls) != DIRECT) {
		    $cls = $ncls;
		    $clen++;
		    next;
		}
		last;
	    } 
	    $width = EA_W;
	} else {
	    $pos++;
	    $width = $self->eawidth($c);
	}
	# After all, possible widths are non-spacing (z), wide (F/W) or
	# narrow (H/N/Na).

	if ($width == EA_z) {
	    $w = 0;
	} elsif ($width == EA_F or $width == EA_W) {
	    $w = 2;
	} else {
	    $w = 1;
	}
	if ($max and $max < $len + $w) {
	    $idx -= length $spc;
	    $idx = 0 unless 0 < $idx;
	    last;
	}
	$idx += $clen;
	$len += $w;
    }

    $max? $idx: $len;
}

1;
