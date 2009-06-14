package Unicode::LineBreak;
require 5.008;

use strict;
use warnings;

sub _loadconst { }
sub _loadlb { }
sub _loadea { }
sub _loadscript { }
sub _loadrule { }
sub _config { }

# _bsearch IDX, VAL
# Examine binary search on property map table with following structure:
# [
#     [start, stop, property_value],
#     ...
# ]
# where start and stop stands for a continuous range of UCS ordinal those
# are assigned property_value.
sub _bsearch {
    my $map = shift;
    my $val = shift;

    my ($top, $bot, $cur);
    my $result = undef;

    $top = 0;
    $bot = $#{$map};
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
    $result;
}

sub eawidth ($$) {
    my $self = shift;
    my $str = shift;
    return undef unless defined $str and length $str;
    my $ret;
    $ret = &_bsearch($self->{_eamap}, ord($str));
    $ret = &_bsearch($Unicode::LineBreak::ea_MAP, ord($str))
	unless defined $ret;
    $ret = EA_N
	unless defined $ret;
    if ($ret == EA_A) {
        if ($self->{Context} eq 'EASTASIAN') {
	    return EA_F;
	}
	return EA_N;
    }
    $ret;
}

sub _gbclass ($$) {
    my $self = shift;
    my $str = shift;
    return undef unless defined $str and length $str;
    my $ret;
    $ret = &_bsearch($self->{_lbmap}, ord($str));
    $ret = &_bsearch($Unicode::LineBreak::lb_MAP, ord($str))
	unless defined $ret;
    $ret = LB_XX
	unless defined $ret;
    if ($ret == LB_AI) {
	return ($self->{Context} eq 'EASTASIAN')? LB_ID: LB_AL;
    } elsif ($ret == LB_SG or $ret == LB_XX) {
	return LB_AL;
    }
    $ret;
}

sub gcinfo ($$$) {
    my $self = shift;
    my $str = shift;
    my $pos = shift;

    my $gcls = undef;
    my ($glen, $elen);
    my ($chr, $nchr);
    my ($cls, $ncls);
    my $str_len;

    return (undef, 0, 0) unless defined $str and length $str;

    $chr = substr($str, $pos, 1);
    $cls = $self->_gbclass($chr);
    $glen = 1;
    $elen = 0;
    $str_len = length $str;

    if ($cls == LB_BK or $cls == LB_LF or $cls == LB_NL) {
	return ($cls, 1, 0);
    } elsif ($cls == LB_CR) {
	$pos++;
	$gcls = $cls;
        if ($pos < $str_len) {
	    $chr = substr($str, $pos, 1);
            $cls = $self->_gbclass($chr);
            if ($cls == LB_LF) {
		$glen++;
	    }
        }
	return ($gcls, $glen, 0);
    } elsif ($cls == LB_SP or $cls == LB_ZW or $cls == LB_WJ) {
	$pos++;
	$gcls = $cls;
	while (1) {
	    last if $str_len <= $pos;
	    $chr = substr($str, $pos, 1);
	    $cls = $self->_gbclass($chr);
	    last unless $cls == $gcls;
	    $pos++;
	    $glen++;
	}
	return ($gcls, $glen, 0);
    # Hangul syllable block
    } elsif ($cls == LB_H2 or $cls == LB_H3 or
	     $cls == LB_JL or $cls == LB_JV or $cls == LB_JT) {
	$pos++;
	$gcls = $cls;
	while (1) {
	    last if $str_len <= $pos;
	    $nchr = substr($str, $pos, 1);
	    $ncls = $self->_gbclass($nchr);
	    if (($ncls == LB_H2 or $ncls == LB_H3 or
		 $ncls == LB_JL or $ncls == LB_JV or $ncls == LB_JT) and
		$self->lbrule($cls, $ncls) != DIRECT) {
		$pos++;
		$glen++;
		$cls = $ncls;
		next;
	    }
	    last;
	} 
    # Extended grapheme base of South East Asian scripts
    } elsif ($cls == LB_SAprepend or $cls == LB_SAbase) {
	$pos++;
	$gcls = LB_AL;
	while (1) {
	    last if $str_len <= $pos;
	    last if $cls == LB_SAbase;
	    $nchr = substr($str, $pos, 1);
	    $ncls = $self->_gbclass($nchr);
	    if ($ncls == LB_SAprepend or $ncls == LB_SAbase) {
		$pos++;
		$glen++;
		$cls = $ncls;
		next;
	    }
	    last;
	} 
    } elsif ($cls == LB_SAextend) {
	$pos++;
	$gcls = LB_CM;
    } else {
	$pos++;
	$gcls = $cls;
    }

    while (1) {
	last if $str_len <= $pos;
	$chr = substr($str, $pos, 1);
	$cls = $self->_gbclass($chr);
	last unless $cls == LB_CM or $cls == LB_SAextend;
	$pos++;
	$elen++;
	$gcls ||= LB_CM;
    }
    return ($gcls, $glen, $elen);
}

sub lbclass ($$) {
    my $self = shift;
    my $str = shift;
    return undef unless defined $str and length $str;
    my $ret = $self->_gbclass($str);
    return LB_AL if $ret == LB_SAprepend or $ret == LB_SAbase;
    return LB_CM if $ret == LB_SAextend;
    $ret;
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
	my ($c, $width, $w);
	my ($gcls, $glen, $elen);
	my $npos;

	last if $length <= $pos;
	($gcls, $glen, $elen) = $self->gcinfo($spcstr, $pos);
	$npos = $pos + $glen + $elen;
	$w = 0;

	# Hangul syllable block
	if ($gcls == LB_H2 or $gcls == LB_H3 or
	    $gcls == LB_JL or $gcls == LB_JV or $gcls == LB_JT) {
	    $w = 2;
	    $pos += $glen;
	}
	while ($pos < $npos) {
	    $c = substr($spcstr, $pos, 1);
	    $width = $self->eawidth($c);
	    if ($width == EA_F or $width == EA_W) { $w += 2; }
	    elsif ($width != EA_Z) { $w += 1; }
	    $pos++;
	}

	if ($max and $max < $len + $w) {
	    $idx -= length $spc;
	    $idx = 0 unless 0 < $idx;
	    last;
	}
	$idx += $glen + $elen;
	$len += $w;
    }

    $max? $idx: $len;
}

package Unicode::LineBreak::SouthEastAsian;

sub break ($) { return (shift); }
sub supported () { return undef; }

1;
