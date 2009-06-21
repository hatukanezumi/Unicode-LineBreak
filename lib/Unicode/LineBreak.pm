#-*- perl -*-

package Unicode::LineBreak;
require 5.008;

### Pragmas:
use strict;
use warnings;
use vars qw($VERSION @EXPORT_OK @ISA $UNICODE_VERSION @LB_CLASSES $Config);

### Exporting:
use Exporter;
our @EXPORT_OK = qw(context MANDATORY DIRECT INDIRECT PROHIBITED);
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);

### Inheritance:
our @ISA = qw(Exporter);

### Other modules:
use Carp qw(croak carp);
use Encode qw(is_utf8);
use MIME::Charset;

### Globals

### The package version
require Unicode::LineBreak::Version;

### Load XS or Non-XS module
eval {
    require XSLoader;
    XSLoader::load('Unicode::LineBreak', $VERSION);
};
if ($@) {
    require Unicode::LineBreak::NoXS;
}

### Public Configuration Attributes
our $Config = {
    CharactersMax => 998,
    ColumnsMin => 0,
    ColumnsMax => 76,
    Context => 'NONEASTASIAN',
    Format => "DEFAULT",
    HangulAsAL => 'NO',
    LegacyCM => 'YES',
    Newline => "\n",
    SizingMethod => 'DEFAULT',
    TailorEA => [],
    TailorLB => [],
    UrgentBreaking => 'NONBREAK',
    UserBreaking => [],
};
eval { require Unicode::LineBreak::Defaults; };

### Exportable constants
use Unicode::LineBreak::Constants;

use constant {
    MANDATORY => M,
    DIRECT => D,
    INDIRECT => I,
    PROHIBITED => P,
    URGENT => 200,
};

use constant 1.01;
my $package = __PACKAGE__;
my @consts = grep { s/^${package}::(\w\w+)$/$1/ } keys %constant::declared;
_loadconst(@consts);
push @EXPORT_OK, @consts;
push @{$EXPORT_TAGS{'all'}}, @consts;

require Unicode::LineBreak::Rules;
_loadrule($Unicode::LineBreak::RULES_MAP);

require Unicode::LineBreak::Data;
_loadlb($Unicode::LineBreak::lb_MAP);
_loadea($Unicode::LineBreak::ea_MAP);
_loadscript($Unicode::LineBreak::script_MAP);

### Privates
my $EASTASIAN_CHARSETS = qr{
    ^BIG5 |
    ^CP9\d\d |
    ^EUC- |
    ^GB18030 | ^GB2312 | ^GBK |
    ^HZ |
    ^ISO-2022- |
    ^KS_C_5601 |
    ^SHIFT_JIS
}ix;

my $EASTASIAN_LANGUAGES = qr{
    ^AIN |
    ^JA\b | ^JPN |
    ^KO\b | ^KOR |
    ^ZH\b | ^CHI
}ix;

# Following table describes built-in behavior by L</Format> options.
#
#       | "DEFAULT"       | "NEWLINE"         | "TRIM"
# ------+-----------------+-------------------+-------------------
# "sot" | 
# "sop" |                   not modify
# "sol" |
# ""    |
# "eol" | append newline  | replace by newline| replace by newline
# "eop" | not modify      | replace by newline| remove SPACEs
# "eot" | not modify      | replace by newline| remove SPACEs
# ----------------------------------------------------------------
my %FORMAT_FUNCS = (
    'DEFAULT' => sub {
	return $_[2].$_[0]->{Newline} if $_[1] eq 'eol';
	undef;
    },
    'NEWLINE' => sub {
	return $_[0]->{Newline} if $_[1] =~ /^eo/;
	undef;
    },
    'TRIM' => sub {
	my $self = shift;
	my $event = shift;
	my $str = shift;
	if ($event eq 'eol') {
	    return $self->{Newline};
	} elsif ($event =~ /^eo/) {
	    $str = substr($str, 1)
		while length $str and $self->lbclass($str) == LB_SP;
	    return $str;
	}
	undef;
    },
);

# Built-in behavior by L</SizingMethod> options.
my %SIZING_FUNCS = (
    'DEFAULT' => \&strsize,
);

# Built-in urgent breaking brehaviors specified by C<UrgentBreaking>.
my %URGENT_BREAKING_FUNCS = (
    'CROAK' => sub { croak "Excessive line was found" },
    'FORCE' => sub {
    my $self = shift;
    my $len = shift;
    my $pre = shift;
    my $spc = shift;
    my $str = shift;
    return () unless length $spc or length $str;

    my $max = $self->{ColumnsMax} || 0;
    my @result = ();

    while (1) {
        my $idx = $self->_sizing($len, $pre, $spc, $str, $max);
        if (0 < $idx) {
	    push @result, substr($str, 0, $idx);
	    $str = substr($str, $idx);
	    last unless length $str;
        } elsif (!$len and $idx <= 0) {
	    push @result, $str;
	    last;
	}
	($len, $pre, $spc) = (0, '', '');
    }
    @result; },
    'NONBREAK' => undef,
);

# Built-in custom breaking behaviors specified by C<UserBreaking>.
my $URIre = qr{(?:https?|s?ftps?)://[\x21-\x7E]+}io;
my %USER_BREAKING_FUNCS = (
    'NONBREAKURI' => [ $URIre, sub { ($_[1]) } ],
    # Breaking URIs according to CMOS:
    # 7.11 1-1: [/] ÷ [^/]
    # 7.11 2:   [-] ×
    # 6.17 2:   [.] ×
    # 7.11 1-2: ÷ [-~.,_?#%]
    # 7.11 1-3: ÷ [=&]
    # 7.11 1-3: [=&] ÷
    # Default:  ALL × ALL
    'BREAKURI' => [ $URIre,
		    sub {
			my @c = split m{
			    (?<=[/]) (?=[^/]) |
			    (?<=[^-.]) (?=[-~.,_?\#%=&]) |
			    (?<=[=&]) (?=.)
			}ox, $_[1];
			# Won't break punctuations at end of matches.
			while (2 <= scalar @c and $c[$#c] =~ /^[.:;,>]+$/) {
			    my $c = pop @c;
			    $c[$#c] .= $c;
			}
			@c;
		    }],
);

sub new ($) {
    my $class = shift;

    my $self = { };
    &config($self, @_);
    &_reset($self);
    bless $self, $class;
}

sub _reset ($) {
    my $self = shift;
    $self->{_line} = {'frg' => '', 'spc' => '', 'cols' => 0};
    $self->{_unread} = '';
    $self->{_sox} = 0;
}

sub break ($$) {
    my $self = shift;
    my $str = shift;
    return '' unless defined $str and length $str;
    return $self->break_partial($str) . $self->break_partial(undef);
}

sub break_partial ($$) {
    my $s = shift;
    my $str = shift;
    my $eot = 0;

    unless (defined $str) { 
	$eot = 1;
	$str = '';
    } elsif ($str =~ /[^\x00-\x7F]/s and !is_utf8($str)) {
        croak "Unicode string must be given."
    }

    ### Initialize status.

    ## Line buffer.
    # frg: Unbreakable text fragment.
    # spc: Trailing spaces.
    # cols: Number of columns of frg.
    my %line = %{$s->{_line}};
    ## ``before'' and ``after'' buffers.
    # cls: Line breaking class.
    # frg: Unbreakable text fragment.
    # spc: Trailing spaces.
    # urg: This buffer had been broken by urgent/custom/complex breaking.
    # eop: There is a mandatory breaking point at end of this buffer.
    my %before = ('frg' => '', 'spc' => '');
    my %after = ('frg' => '', 'spc' => '');
    ## Unread input.
    $str = $s->{_unread}.$str;
    ## Start of text/paragraph status.
    # 0: Start of text not done.
    # 1: Start of text done while start of paragraph not done.
    # 2: Start of paragraph done.
    my $sox = $s->{_sox};

    ## Result.
    my $result = '';
    ## Queue of buffers broken by urgent/custom/complex breaking.
    my @custom = ();
    ## Current position and length of STR.
    my $pos = 0;
    my $str_len = length $str;

    while (1) {
	### Chop off a pair of unbreakable character clusters from text.

      CHARACTER_PAIR:
	while (1) {
	    my ($gcls, $glen, $elen);

	    # End of input.
	    last CHARACTER_PAIR if !scalar(@custom) and $str_len <= $pos;
	    # Mandatory break
	    last CHARACTER_PAIR if defined $before{cls} and $before{eop};

	    ## Use custom buffer at first.
	    if (!scalar(@custom)) {
		## Then, go ahead reading input.

		#
		# Append SP/ZW/eop to ``before'' buffer.
		#

		while (1) {
		    ($gcls, $glen, $elen) = $s->gcinfo($str, $pos);

		    # - Explicit breaks and non-breaks

		    # LB7(1): × SP+
		    if ($gcls == LB_SP) {
			$before{spc} .= substr($str, $pos, $glen);
			$pos += $glen;
			# Treat (sot | eop) SP+  as if it were WJ.
			$before{cls} = LB_WJ unless defined $before{cls};

			# End of input.
			last CHARACTER_PAIR if $str_len <= $pos;
			($gcls, $glen, $elen) = $s->gcinfo($str, $pos);
		    }

		    # - Mandatory breaks

		    # LB4 - LB7: × SP* (BK | CR LF | CR | LF | NL) !
		    if ($gcls == LB_BK or $gcls == LB_CR or $gcls == LB_LF or
			$gcls == LB_NL) {
			$before{spc} .= substr($str, $pos, $glen);
			$pos += $glen;
			$before{cls} = $gcls;
			$before{eop} = 1
			    unless !$eot and $gcls == LB_CR and
			    $glen == 1 and $str_len <= $pos;
			last CHARACTER_PAIR;
		    }

		    # - Explicit breaks and non-breaks

		    # LB7(2): × (SP* ZW+)+
		    if ($gcls == LB_ZW) {
			$before{frg} .= $before{spc}.substr($str, $pos, $glen);
			$pos += $glen;
			$before{spc} = '';
			$before{cls} = LB_ZW;

			# End of input
			last CHARACTER_PAIR if $str_len <= $pos;
			($gcls, $glen, $elen) = $s->gcinfo($str, $pos);
			next;
		    }
		    last;
		} # while (1)

		#
		# Fill custom buffer and retry
		#
		my @c;
		# Try custom breaking.
		my $len;
		if (scalar(@c = $s->_test_custom($str, $pos, \$len))) {
		    # End of input - might be partial match.
		    if (!$eot and $str_len <= $pos + $len) {
			$s->{_line} = \%line;
			$s->{_unread} =
			    $before{frg}.$before{spc}.substr($str, $pos);
			$s->{_sox} = $sox;
			return $result;
		    }
		    $pos += $len;
		    push @custom, @c;
		    next;
		}

		# Try complex breaking - Break SA sequence.
		if ($gcls == LB_SA) {
		    my $frg = '';
		    $frg .= substr($str, $pos, $glen + $elen);
		    $pos += $glen + $elen;

		    # End of input - might be partial sequence.
		    if (!$eot and $str_len <= $pos) {
			$s->{_line} = \%line;
			$s->{_unread} = $before{frg}.$before{spc}.$frg;
			$s->{_sox} = $sox;
			return $result;
		    }
		    @c = map { {'cls' => LB_AL, 'frg' => $_, 'spc' => '',
				'urg' => 1}; }
			     Unicode::LineBreak::SouthEastAsian::break($frg);
		    if (scalar @c) {
			$c[$#c]->{urg} = 0;
			unshift @custom, @c;
		    }
		    next;
		}

		#
		# Then fill ``after'' buffer.
		#

		# - Rules for other line breaking classes

		# LB1: Assign a line breaking class to each characters.
		%after = ('frg' => substr($str, $pos, $glen + $elen),
			  'spc' => '');
		$pos += $glen + $elen;
		# LB27: Treate hangul syllable as if it were ID (or AL).
		if ($gcls == LB_H2 or $gcls == LB_H3 or
		    $gcls == LB_JL or $gcls == LB_JV or $gcls == LB_JT) {
		    $after{cls} = ($s->{HangulAsAL} eq 'YES')? LB_AL: LB_ID;
		# Legacy-CM: Treat SP CM+ as if it were ID.  cf. [UAX #14] 9.1.
		# LB10: Treat any remaining CM+ as if it were AL.
		} elsif ($gcls == LB_CM) {
		    if ($s->{LegacyCM} eq 'YES' and
			defined $before{cls} and length $before{spc} and
			$s->lbclass(substr($before{spc}, -1)) == LB_SP) {
			$after{frg} = substr($before{spc}, -1).$after{frg};
			$after{cls} = LB_ID;

			# clear ``before'' buffer if it was empty.
			$before{spc} =
			    substr($before{spc}, 0, length($before{spc}) - 1);
			$before{cls} = undef
			    unless length $before{frg} or length $before{spc};
		    } else {
			$after{cls} = LB_AL;
		    }
		} else {
		    $after{cls} = $gcls;
		}
	    } else {
		%after = (%{shift @custom});
	    } # if (!scalar(@custom))

	    # - Start of text

	    # LB2: sot ×
	    last if defined $before{cls};

	    # shift buffers.
	    %before = (%after);
	    %after = ('frg' => '', 'spc' => '');
	} # CHARACTER_PAIR: while (1)

	## Determin line breaking action by classes of adjacent characters.
	## URGENT is used only internally.

	my $action;

	# Mandatory break.
	if ($before{eop}) {
	    $action = MANDATORY;
	# Broken by urgent breaking or custom breaking.
	} elsif ($before{urg}) {
	    $action = URGENT;
	# LB11 - LB29 and LB31: Tailorable rules (except LB11, LB12).
	} elsif (defined $after{cls}) {
	    $action = $s->lbrule($before{cls}, $after{cls});

	    # Check prohibited break.
	    if ($action == PROHIBITED or
		$action == INDIRECT and !length $before{spc}) {

		# When conjunction of $before{frg} and $after{frg} is
		# expected to exceed CharactersMax, try urgent breaking.
		my $bsa = $before{frg}.$before{spc}.$after{frg};
		if ($s->{CharactersMax} < length $bsa) {
		    my @c = $s->_urgent_break(0, '', '',
					      $after{cls}, $bsa, $after{spc});
		    my @cc = ();

		    # When urgent break wasn't carried out and $before{frg}
		    # was not longer than CharactersMax, break between
		    # $before{frg} and $after{frg} so that character clusters
		    # might not be broken.
		    if (scalar @c == 1 and $c[0]->{frg} eq $bsa and
			length $before{frg} <= $s->{CharactersMax}) {
			push @cc, {%before};
			$cc[0]->{cls} = LB_XX;
			$cc[0]->{urg} = 1;
			push @cc, {%after};
		    # Otherwise, if any of urgently broken fragments still
		    # exceed CharactersMax, force chop them.
		    } else {
			foreach my $c (@c) {
			    my ($cls, $frg, $spc, $urg) =
				($c->{cls}, $c->{frg}, $c->{spc}, $c->{urg});
			    while ($s->{CharactersMax} < length $frg) {
				my $b = substr($frg, 0, $s->{CharactersMax});
				$frg = substr($frg, $s->{CharactersMax});
				if ($s->lbclass($frg) == LB_CM) {
				    while (length $b) {
					my $t = substr($b, -1);
					$b = substr($b, length($b) - 1);
					$frg = $t.$frg;
					unless ($s->lbclass($t) == LB_CM) {
					    last;
					}
				    }
				}
				if (length $b) {
				    push @cc, {'cls' => LB_XX, 'frg' => $b,
					       'spc' => '', 'urg' => 1};
				}
			    }
			    push @cc, {'cls' => $cls, 'frg' => $frg,
				       'spc' => $spc, 'urg' => $urg};
			}
			if (scalar @cc) {
			    $cc[$#cc]->{eop} = $after{eop};
			    # As $after{frg} may be an incomplete fragment,
			    # urgent break won't be carried out at its end.
			    $cc[$#cc]->{urg} = 0;
			}
		    }

		    # Shift back urgently broken fragments then retry.
		    unshift @custom, @cc;
		    %before = ('frg' => '', 'spc' => '');
		    %after = ('frg' => '', 'spc' => '');
		    next;
		} 
		# Otherwise, fragments may be conjuncted safely.  Read more.
		my $frg = $before{frg}.$before{spc}.$after{frg};
		%before = (%after); $before{frg} = $frg;
		%after = ('frg' => '', 'spc' => '');
		next;
	    } # if ($action == PROHIBITED or ...)
	} # if ($before{eop})

        # Check end of input.
        if (!$eot and !defined $after{cls} and
	    !scalar @custom and $str_len <= $pos) {
	    # Save status then output partial result.
	    $s->{_line} = \%line;
	    $s->{_unread} = $before{frg}.$before{spc};
	    $s->{_sox} = $sox;
	    return $result;
        }

	# After all, possible actions are MANDATORY and other arbitrary.

	### Examine line breaking action

	if ($sox == 0) { # sot undone.
	    # Process start of text.
	    $before{frg} = $s->_format('sot', $before{frg});
	    $sox = 1;
	} elsif ($sox == 1) { # sop undone.
	    # Process start of paragraph.
	    $before{frg} = $s->_format('sop', $before{frg});
	    $sox = 2;
	}

	# Check if arbitrary break is needed.
	my $newcols = $s->_sizing($line{cols}, $line{frg}, $line{spc},
				  $before{frg});
	if ($s->{ColumnsMax} and $s->{ColumnsMax} < $newcols) {
	    $newcols = $s->_sizing(0, '', '', $before{frg}); 

	    # When arbitrary break is expected to generate very short line,
	    # or when $before{frg} will exceed ColumnsMax, try urgent breaking.
	    unless ($before{urg}) {
		my @c = ();
		if ($line{cols} and $line{cols} < $s->{ColumnsMin}) {
		    @c = $s->_urgent_break($line{cols}, $line{frg}, $line{spc},
					   $before{cls}, $before{frg},
					   $before{spc});
		} elsif ($s->{ColumnsMax} < $newcols) {
		    @c = $s->_urgent_break(0, '', '',
					   $before{cls}, $before{frg},
					   $before{spc});
		}
		if (scalar @c) {
		    push @c, {%after} if defined $after{cls};
		    unshift @custom, @c;
		    %before = ('frg' => '', 'spc' => '');
		    %after = ('frg' => '', 'spc' => '');
		    next;
		}
	    }

	    # Otherwise, process arbitrary break.
	    if (length $line{frg} or length $line{spc}) {
		$result .= $s->_format('', $line{frg});
		$result .= $s->_format('eol', $line{spc});
		my $bak = $before{frg};
		$before{frg} = $s->_format('sol', $before{frg});
		$newcols = $s->_sizing(0, '', '', $before{frg})
		    unless $bak eq $before{frg};
	    }
	    %line = ('frg' => $before{frg},
		     'spc' => $before{spc}, 'cols' => $newcols);
	# Arbitrary break is not needed.
	} else {
	    %line = ('frg' => $line{frg}.$line{spc}.$before{frg},
		     'spc' => $before{spc}, 'cols' => $newcols);
	} # if ($s->{ColumnsMax} and ...)

	# Mandatory break or end-of-text.
	if ($eot and !defined $after{cls} and
	    !scalar @custom and $str_len <= $pos) {
	    last;
	}
	if ($action == MANDATORY) {
	    # Process mandatory break.
	    $result .= $s->_format('', $line{frg});
	    $result .= $s->_format('eop', $line{spc});
	    $sox = 1; # eop done then sop must be carried out.
	    %line = ('frg' => '', 'spc' => '', 'cols' => 0);
	}

	# Shift buffers.
	%before = (%after);
	%after = ('frg' => '', 'spc' => '');
    } # TEXT: while (1)

    # Process end of text.
    $result .= $s->_format('', $line{frg});
    $result .= $s->_format('eot', $line{spc});

    ## Reset status then return the rest of result.
    $s->_reset;
    $result;
}

sub config ($@) {
    my $self = shift;
    my %params = @_;
    my @opts = qw{CharactersMax ColumnsMin ColumnsMax Context Format
		      HangulAsAL LegacyCM Newline SizingMethod
		      TailorEA TailorLB UrgentBreaking UserBreaking};

    # Get config.
    if (scalar @_ == 1) {
	foreach my $o (@opts) {
	    if (uc $_[0] eq uc $o) {
		return $self->{$o};
	    }
	}
	croak "No such option: $_[0]";
    }

    # Set config.
    foreach my $k (keys %params) {
	my $v = $params{$k};
	foreach my $o (@opts) {
	    if (uc $k eq uc $o) {
		$self->{$o} = $v;
	    }
	}
    }

    # Format method.
    $self->{Format} ||= $Config->{Format};
    unless (ref $self->{Format}) {
	$self->{Format} = uc $self->{Format};
	$self->{_format_func} =
	    $FORMAT_FUNCS{$self->{Format}} || $FORMAT_FUNCS{'DEFAULT'};
    } else {
	$self->{_format_func} = $self->{Format};
    }
    # Sizing method
    $self->{SizingMethod} ||= $Config->{SizingMethod};
    unless (ref $self->{SizingMethod}) {
	$self->{SizingMethod} = uc $self->{SizingMethod};
	$self->{_sizing_func} =
	    $SIZING_FUNCS{$self->{SizingMethod}} || $SIZING_FUNCS{'DEFAULT'};
    } else {
	$self->{_sizing_func} = $self->{SizingMethod};
    }
    # Urgent break
    $self->{UrgentBreaking} ||= $Config->{UrgentBreaking};
    unless (ref $self->{UrgentBreaking}) {
	$self->{UrgentBreaking} = uc $self->{UrgentBreaking};
	$self->{_urgent_breaking_func} =
	    $URGENT_BREAKING_FUNCS{$self->{UrgentBreaking}} || undef;
    } else {
	$self->{_urgent_breaking_func} = $self->{UrgentBreaking};
    }
    # Custom break
    $self->{UserBreaking} ||= $Config->{UserBreaking};
    $self->{UserBreaking} = [$self->{UserBreaking}]
	unless ref $self->{UserBreaking};
    my @cf = ();
    foreach my $ub (@{$self->{UserBreaking}}) {
	next unless defined $ub;
	unless (ref $ub) {
	    $ub = $USER_BREAKING_FUNCS{uc $ub};
	    next unless defined $ub;
	}
	my ($re, $func) = @{$ub};
	push @cf, [qr{\G($re)}o, $func];
    }
    $self->{_custom_funcs} = \@cf;

    # Context. Either East Asian or Non-East Asian.
    my $context = uc($self->{Context} || $Config->{Context});
    if ($context =~ /^(N(ON)?)?EA(STASIAN)?/) {
	if ($context =~ /^N/) {
	    $context = 'NONEASTASIAN';
	} else {
	    $context = 'EASTASIAN';
	}
    }
    $self->{Context} = $context;

    # Flags
    my $o;
    foreach $o (qw{LegacyCM HangulAsAL}) {
	$self->{$o} = $Config->{$o} unless defined $self->{$o};
	if (uc $self->{$o} eq 'YES') {
	    $self->{$o} = 'YES';
	} elsif ($self->{$o} =~ /^\d/ and $self->{$o}+0) {
	    $self->{$o} = 'YES';
	} else {
	    $self->{$o} = 'NO';
	}
    }

    ## Classes
    foreach $o (qw{TailorLB TailorEA}) {
	$self->{$o} = [@{$Config->{$o}}]
	    unless defined $self->{$o} and ref $self->{$o};
	my @v = @{$self->{$o}};
	my %map = ();
	while (scalar @v) {
	    my $k = shift @v;
	    my $v = shift @v;
	    next unless defined $k and defined $v;
	    if (ref $k) {
		foreach my $c (@{$k}) {
		    $map{$c} = $v;
		}
	    } else {
		$map{$k} = $v;
	    }
	}
	my @map = ();
	my ($beg, $end) = (undef, undef);
	my $p;
	foreach my $c (sort {$a <=> $b} keys %map) {
	    unless ($map{$c}) {
		next;
	    } elsif (defined $end and $end + 1 == $c and $p eq $map{$c}) {
		$end = $c;
	    } else {
		if (defined $beg and defined $end) {
		    push @map, [$beg, $end, $p];
		}
		$beg = $end = $c;
		$p = $map{$c};
	    }
	}
	if (defined $beg and defined $end) {
	    push @map, [$beg, $end, $p];
	}
	if ($o eq 'TailorLB') {
	    $self->{_lbmap} = \@map;
	} elsif ($o eq 'TailorEA') {
	    $self->{_eamap} = \@map;
	}
    }

    # Other options
    foreach $o (qw{CharactersMax ColumnsMin ColumnsMax Newline}) {
	$self->{$o} = $Config->{$o} unless defined $self->{$o};
    }

    &_config($self);
}

sub context (@) {
    my %opts = @_;

    my $charset;
    my $language;
    my $context;
    foreach my $k (keys %opts) {
	if (uc $k eq 'CHARSET') {
	    if (ref $opts{$k}) {
		$charset = $opts{$k}->as_string;
	    } else {
		$charset = MIME::Charset->new($opts{$k})->as_string;
	    }
	} elsif (uc $k eq 'LANGUAGE') {
	    $language = uc $opts{$k};
	    $language =~ s/_/-/;
	}
    }
    if ($charset and $charset =~ /$EASTASIAN_CHARSETS/) {
        $context = 'EASTASIAN';
    } elsif ($language and $language =~ /$EASTASIAN_LANGUAGES/) {
	$context = 'EASTASIAN';
    } else {
	$context = 'NONEASTASIAN';
    }
    $context;
}

sub _format ($$$) {
    my $self = shift;
    my $action = shift || '';
    my $str = shift;

    my $result;
    my $err = $@;
    eval {
	$result = &{$self->{_format_func}}($self, $action, $str);
    };
    if ($@) {
	carp $@;
	$result = $str;
    } elsif (!defined $result) {
	$result = $str;
    }
    $@ = $err;
    return $result;
}

sub _urgent_break ($$$$$$$) {
    my $self = shift;
    my $l_len = shift;
    my $l_frg = shift;
    my $l_spc = shift;
    my $cls = shift;
    my $frg = shift;
    my $spc = shift;

    if (ref $self->{_urgent_breaking_func}) {
	my @broken = map { {'cls' => LB_XX, 'frg' => $_, 'spc' => '',
			    'urg' => 1}; }
	&{$self->{_urgent_breaking_func}}($self, $l_len, $l_frg, $l_spc, $frg);
	$broken[$#broken]->{cls} = $cls;
	$broken[$#broken]->{spc} = $spc;
	return @broken;
    }
    return ({'cls' => $cls, 'frg' => $frg, 'spc' => $spc, 'urg' => 1});
}

sub _test_custom ($$$) {
    my $self = shift;
    my $str = shift;
    my $pos = shift;
    my $lenref = shift;
    my @custom = ();

    pos($str) = $pos;
    foreach my $c (@{$self->{_custom_funcs}}) {
	my ($re, $func) = @{$c};
	if ($str =~ /$re/cg) {
	    my $frg = $1;
	    foreach my $b (&{$func}($self, $frg)) {
		my $s = '';
		while (length $b and
		       $self->lbclass(substr($b, -1)) == LB_SP) {
		    $s = substr($b, -1).$s;
		    $b = substr($b, 0, length($b) - 1);
		}
		if (length $b) {
		    push @custom, {'cls' => LB_XX, 'frg' => $b, 'spc' => $s,
				   'urg' => 1};
		} elsif (scalar @custom) {
		    $custom[$#custom]->{spc} .= $s;
		} elsif (length $s) {
		    push @custom, {'cls' => LB_XX, 'frg' => $b, 'spc' => $s,
				   'urg' => 1};
		}
	    }
	    last;
	}
    }
    $$lenref = pos($str) - $pos;
    return @custom;
}

sub _sizing ($$$$$;$) {
    my $self = shift;
    my $size = &{$self->{_sizing_func}}($self, @_);
    $size = $self->strsize(@_) unless defined $size;
    $size;
}

1;
