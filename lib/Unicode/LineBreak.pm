#-*- perl -*-

package Unicode::LineBreak;
require 5.008;

### Pragmas:
use strict;
use warnings;
use vars qw($VERSION @EXPORT_OK @ISA $UNICODE_VERSION @LB_CLASSES $Config);

### Exporting:
use Exporter;
our @EXPORT_OK = qw(getcontext MANDATORY DIRECT INDIRECT PROHIBITED);
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
    NSKanaAsID => 'NO',
    SizingMethod => 'DEFAULT',
    UrgentBreaking => 'NONBREAK',
    UserBreaking => [],
};
eval { require Unicode::LineBreak::Defaults; };

### Exportable constants
use Unicode::LineBreak::Constants;

push @EXPORT_OK, @LB_CLASSES;
push @{$EXPORT_TAGS{'all'}}, @LB_CLASSES;
$EXPORT_TAGS{'class'} = [@LB_CLASSES];

use constant EOT => 100;
use constant MANDATORY => M;
use constant DIRECT => D;
use constant INDIRECT => I;
use constant PROHIBITED => P;
use constant URGENT => 200;

### Privates
_loadconst(LB_XX, DIRECT);
require Unicode::LineBreak::Rules;
_loadrule($Unicode::LineBreak::RULES_MAP);
require Unicode::LineBreak::Data;
_loadmap(0, $Unicode::LineBreak::lb_MAP);
_loadmap(1, $Unicode::LineBreak::ea_MAP);

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
		while length $str and $self->getlbclass($str) == LB_SP;
	    return $str;
	}
	undef;
    },
);

# Built-in behavior by L</SizingMethod> options.
my %SIZING_FUNCS = (
    'DEFAULT' => \&getstrsize,
    'NARROWAL' => \&getstrsize,
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

    my @result = ();

    while (1) {
        my $idx =  &{$self->{_sizing_func}}($self, $len, $pre, $spc, $str,
					    $self->{ColumnsMax});
	$idx = $self->getstrsize($len, $pre, $spc, $str, $self->{ColumnsMax})
	    unless defined $idx;
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
my $URIre = qr{(?:https?|s?ftps?)://[\x{0021}-\x{007E}]+}io;
my %USER_BREAKING_FUNCS = (
    'NONBREAKURI' => [ $URIre, sub { ($_[1]) } ],
    'BREAKURI' => [ $URIre,
		    sub { ($_[1] =~ m{(?:^.+?//[^/]*|/[^/]*)}go) } ],
);

sub new {
    my $class = shift;

    my $self = { };
    &config($self, @_);
    bless $self, $class;
}

sub break {
    my $s = shift;
    my $str = shift;
    return '' unless defined $str and length $str;
    croak "Unicode string must be given."
	if $str =~ /[^\x00-\x7F]/s and !is_utf8($str);

    ## Initialize status.

    # Result.
    my $result = '';

    # Line buffer.
    my ($l_frg, $l_spc, $l_len) = ('', '', 0);

    # ``before'' and ``after'' buffers.
    # cls: line breaking class.
    # frg: unbreakable text fragment.
    # spc: trailing spaces.
    # urg: frg has been broken by urgent breaking.
    # eop: the end of frg is mandatory breaking point.
    # eot: frg is at end of text.
    my %before = ('frg' => '', 'spc' => '');
    my %after;

    # Queue of urgent/custom broken fragments.
    my @custom = ();

    # Initially, "sot" event has not yet done and "sop" event is inhibited.
    my $sot_done = 0;
    my $sop_done = 1;

    # Current position and length of STR.
    my $pos = 0;
    my $str_len = length $str;
    while (1) {
	### Chop off a pair of unbreakable character clusters from text.

      CHARACTER_PAIR:
	while (1) {
	    my ($frg, $cls);

	    %before = (%after)
		if !defined $before{cls} and defined $after{cls};
	    %after = ('frg' => '', 'spc' => '');
	    last CHARACTER_PAIR
		if defined $before{cls} and ($before{eop} or $before{eot});

	    ## Use custom buffer at first.
	    if (!scalar(@custom)) {
		## Then, go ahead reading input.

		#
		# Append SP/ZW/eop to ``before'' buffer.
		#

		while (1) {
		    # - End of text

		    # LB3: ! eot
		    if ($str_len <= $pos) {
			$before{eot} = 1;
			last CHARACTER_PAIR;
		    }
		    $frg = substr($str, $pos, 1);
		    $cls = $s->getlbclass($frg);

		    # - Explicit breaks and non-breaks

		    # LB7(1): × SP+
		    while ($cls == LB_SP) {
			$pos++;
			$before{spc} .= $frg;
			# Treat (sot | eop) SP+  as if it were WJ.
			$before{cls} = LB_WJ unless defined $before{cls};

			if ($str_len <= $pos) {
			    $before{eot} = 1;
			    last CHARACTER_PAIR;
			}
			$frg = substr($str, $pos, 1);
			$cls = $s->getlbclass($frg);
		    }

		    # - Mandatory breaks

		    # LB4 - LB7: × SP* (BK | CR LF | CR | LF | NL) !
		    if ($cls == LB_BK or $cls == LB_CR or $cls == LB_LF or
			$cls == LB_NL) {
			$pos++;
			$before{spc} .= $frg; # $before{spc} = SP* (BK etc.)
			$before{cls} = $cls;
			$before{eop} = 1;
			if ($pos < $str_len and $cls == LB_CR) {
			    $frg = substr($str, $pos, 1);
			    $cls = $s->getlbclass($frg);
			    if ($cls == LB_LF) {
				$pos++;
				$before{spc} .= $frg;
			    }
			}

			# LB3: ! eot
			if ($str_len <= $pos) {
			    $before{eot} = 1;
			}
			last CHARACTER_PAIR;
		    }

		    # - Explicit breaks and non-breaks

		    # LB7(2): × (SP* ZW+)+
		    if ($cls == LB_ZW) {
			while ($cls == LB_ZW) {
			    $pos++;
			    $before{frg} .= $before{spc}.$frg;
			    $before{spc} = '';
			    $before{cls} = LB_ZW;

			    if ($str_len <= $pos) {
				$before{eot} = 1;
				last CHARACTER_PAIR;
			    }
			    $frg = substr($str, $pos, 1);
			    $cls = $s->getlbclass($frg);
			}
			next;
		    }
		    last;
		} # while (1)

		#
		# Fill custom buffer and retry
		#
		my @c;
		if (scalar(@c = $s->_test_custom($str, \$pos))) {
		    push @custom, @c;
		    next;
		}

		#
		# Then fill ``after'' buffer.
		#

		# - Rules for other line breaking classes

		# LB1: Assign a line breaking class to each characters.
		$pos++;
		%after = ('cls' => $cls, 'frg' => $frg, 'spc' => '');

		# LB26, LB27: Treat
		#   (JL* H3 JT* | JL* H2 JV* JT* | JL* JV+ JT* | JL+ | JT+)
		# as if it were ID or, optionally, AL.
		# N.B.: [UAX #14] allows some morbid "Korean syllable blocks"
		# such as
		#   JL CM JV JT
		# which might be broken to JL CM and rest.  Maybe this rule is
		# non-tailorable: cf. Unicode Standard section 3.12
		# `Conjoining Jamo Behavior'.
		if ($cls == LB_JL or $cls == LB_JV or $cls == LB_JT or
		    $cls == LB_H2 or $cls == LB_H3) {
		    my $pcls = $cls;
		    while ($pos < $str_len) {
			$frg = substr($str, $pos, 1);
			$cls = $s->getlbclass($frg);
			if (($cls == LB_JL or $cls == LB_JV or $cls == LB_JT or
			     $cls == LB_H2 or $cls == LB_H3) and
			    $s->getlbrule($pcls, $cls) != DIRECT) {
			    $pos++;
			    $after{frg} .= $frg;
			    $pcls = $cls;
			    next;
			}
			last;
		    }
		    $after{cls} = ($s->{HangulAsAL} eq 'YES')? LB_AL: LB_ID;
		}

		# - Combining marks

		# LB9: Treat X CM+ as if it were X
		# where X is anything except BK, CR, LF, NL, SP or ZW
		while ($pos < $str_len) {
		    $frg = substr($str, $pos, 1);
		    $cls = $s->getlbclass($frg);
		    last unless $cls == LB_CM;
		    $pos++;
		    $after{frg} .= $frg;
		}		    

		# Legacy-CM: Treat SP CM+ as if it were ID.  cf. [UAX #14] 9.1.
		# LB10: Treat any remaining CM+ as if it were AL.
		if ($after{cls} == LB_CM) {
		    if ($s->{LegacyCM} eq 'YES' and
			defined $before{cls} and length $before{spc} and
			$s->getlbclass(substr($before{spc}, -1)) == LB_SP) {
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
		}
	    } else {
		%after = (%{shift @custom});
	    } # if (!scalar(@custom))

	    # - Start of text

	    # LB2: sot ×
	    last if defined $before{cls};
	} # CHARACTER_PAIR: while (1)

	## Determin line breaking action by classes of adjacent characters.
	## EOT is used only internally.

	my $action;
	# End of text.
	if ($before{eot}) {
	    $action = EOT;
        # Mandatory break.
	} elsif ($before{eop}) {
	    $action = MANDATORY;
	# Broken by urgent breaking or custom breaking.
	} elsif ($before{urg}) {
	    $action = URGENT;
	# LB11 - LB29 and LB31: Tailorable rules (except LB11, LB12).
	} else {
	    $action = $s->getlbrule($before{cls}, $after{cls});

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
				if ($s->getlbclass($frg) == LB_CM) {
				    while (length $b) {
					my $t = substr($b, -1);
					$b = substr($b, length($b) - 1);
					$frg = $t.$frg;
					unless ($s->getlbclass($t) == LB_CM) {
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
			    $cc[$#cc]->{eot} = $after{eot};
			    # As $after{frg} may be an imcomplete fragment,
			    # urgent break won't be carried out at its end.
			    $cc[$#cc]->{urg} = 0;
			}
		    }

		    # Shift back urgently broken fragments then retry.
		    unshift @custom, @cc;
		    if (scalar @custom) {
			%before = (%{shift @custom}); #XXX maybe eop/eot
		    } else {
			%before = ('frg' => '', 'spc' => '');
		    }
		    next;
		} 
		# Otherwise, fragments may be conjuncted safely.  Read more.
		my $frg = $before{frg}.$before{spc}.$after{frg};
		%before = (%after); #XXX maybe eop/eot
		$before{frg} = $frg;
		next;
	    } # if ($action == PROHIBITED or ...)
	} # if ($before{eot})
	# After all, possible actions are EOT, MANDATORY and other arbitrary.

	### Examine line breaking action

	if (!$sot_done) {
	    # Process start of text.
	    $before{frg} = $s->_format('sot', $before{frg});
	    $sot_done = 1;
	    $sop_done = 1;
	} elsif (!$sop_done) {
	    # Process start of paragraph.
	    $before{frg} = $s->_format('sop', $before{frg});
	    $sop_done = 1;
	}
	
	# Check if arbitrary break is needed.
	my $l_newlen =
	    &{$s->{_sizing_func}}($s, $l_len, $l_frg, $l_spc, $before{frg});
	if ($s->{ColumnsMax} and $s->{ColumnsMax} < $l_newlen) {
	    $l_newlen = &{$s->{_sizing_func}}($s, 0, '', '', $before{frg}); 

	    # When arbitrary break is expected to generate very short line,
	    # or when $before{frg} will exceed ColumnsMax, try urgent breaking.
	    unless ($before{urg}) {
		my @c = ();
		if ($l_len and $l_len < $s->{ColumnsMin}) {
		    @c = $s->_urgent_break($l_len, $l_frg, $l_spc,
					   $before{cls}, $before{frg},
					   $before{spc});
		} elsif ($s->{ColumnsMax} < $l_newlen) {
		    @c = $s->_urgent_break(0, '', '',
					   $before{cls}, $before{frg},
					   $before{spc});
		}
		if (scalar @c) {
		    push @c, {%after} if defined $after{cls};
		    unshift @custom, @c;
		    if (scalar @custom) {
			%before = (%{shift @custom}); #XXX maybe eop/eot
		    } else {
			%before = ('frg' => '', 'spc' => '');
		    }
		    next;
		}
	    }

	    # Otherwise, process arbitrary break.
	    if (length $l_frg.$l_spc) {
		$result .= $s->_format('', $l_frg);
		$result .= $s->_format('eol', $l_spc);
		my $bak = $before{frg};
		$before{frg} = $s->_format('sol', $before{frg});
		$l_newlen = &{$s->{_sizing_func}}($s, 0, '', '', $before{frg})
		    unless $bak eq $before{frg};
	    }
	    $l_frg = $before{frg};
	    $l_len = $l_newlen;
	    $l_spc = $before{spc};
	# Arbitrary break is not needed.
	} else {
	    $l_frg .= $l_spc;
	    $l_frg .= $before{frg};
	    $l_len = $l_newlen;
	    $l_spc = $before{spc};
	} # if ($s->{ColumnsMax} and ...)

	# Mandatory break or end-of-text.
	if ($action == MANDATORY) {
	    # Process mandatory break.
	    $result .= $s->_format('', $l_frg);
	    $result .= $s->_format('eop', $l_spc);
	    $sop_done = 0;
	    $l_frg = '';
	    $l_len = 0;
	    $l_spc = '';
	} elsif ($action == EOT) {
	    # Process end of text.
	    $result .= $s->_format('', $l_frg);
	    $result .= $s->_format('eot', $l_spc);
	    last;
	}

	# Shift buffer.
	%before = (%after);
    } # while (1)

    ## Return result.
    $result;
}

sub config {
    my $self = shift;
    my %params = @_;
    my @opts = qw{CharactersMax ColumnsMin ColumnsMax Context Format
		      HangulAsAL LegacyCM Newline NSKanaAsID
		      SizingMethod UrgentBreaking UserBreaking};

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
    my $narrowal;
    $self->{SizingMethod} ||= $Config->{SizingMethod};
    unless (ref $self->{SizingMethod}) {
	$self->{SizingMethod} = uc $self->{SizingMethod};
	$self->{_sizing_func} =
	    $SIZING_FUNCS{$self->{SizingMethod}} || $SIZING_FUNCS{'DEFAULT'};
	$narrowal = $self->{SizingMethod} eq 'NARROWAL'? 1: 0;
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
    my $v = $self->{'NSKanaAsID'};
    $v = $Config->{NSKanaAsID} unless defined $v;
    $v = 'ALL' if uc $v =~ m/^(YES|ALL)$/ or $v =~ /^\d/ and $v+0;
    my @v = ();
    push @v, 'ITERATION MARKS'          if $v eq 'ALL' or $v =~ /ITER/i;
    push @v, 'KANA SMALL LETTERS'       if $v eq 'ALL' or $v =~ /SMALL/i;
    push @v, 'PROLONGED SOUND MARKS'    if $v eq 'ALL' or $v =~ /LONG/i;
    push @v, 'MASU MARK'                if $v eq 'ALL' or $v =~ /MASU/i;
    $self->{'NSKanaAsID'} = join(',', @v) || 'NO';

    ## Customization of character properties and rules.
    # Resolve AI, SA, SG, XX.  Won't resolve CB.
    $self->{_lb_hash} = &_packed_hash
	(LB_SAal() => LB_AL,
	 LB_SAcm() => LB_CM,
	 LB_SG() => LB_AL,
	 LB_XX() => LB_AL,
	 LB_AI() => ($self->{Context} eq 'EASTASIAN'? LB_ID: LB_AL),
	 LB_NSidIter() => ($self->{NSKanaAsID} =~ /ITER/? LB_ID: LB_NS),
	 LB_NSidKana() => ($self->{NSKanaAsID} =~ /SMALL/? LB_ID: LB_NS),
	 LB_NSidLong() => ($self->{NSKanaAsID} =~ /LONG/? LB_ID: LB_NS),
	 LB_NSidMasu() => ($self->{NSKanaAsID} =~ /MASU/? LB_ID: LB_NS),
	 );
    # Resolve ambiguous (A) characters to either neutral (N) or fullwidth (F).
    if ($self->{Context} eq 'EASTASIAN') {
	$self->{_ea_hash} = &_packed_hash
	    (EA_A() => EA_F,
	     EA_AnLat() => ($narrowal? EA_N: EA_F),
	     EA_AnGre() => ($narrowal? EA_N: EA_F),
	     EA_AnCyr() => ($narrowal? EA_N: EA_F)
	     );
    } else {
	$self->{_ea_hash} = &_packed_hash
	    (EA_A() => EA_N,
	     EA_AnLat() => EA_N,
	     EA_AnGre() => EA_N,
	     EA_AnCyr() => EA_N
	     );
    }
    # Core rules: No customization.
    $self->{_rule_hash} = &_packed_hash();

    # Other options
    foreach $o (qw{CharactersMax ColumnsMin ColumnsMax Newline}) {
	$self->{$o} = $Config->{$o} unless defined $self->{$o};
    }
}

sub getcontext {
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

sub getstrsize {
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
	my ($clen, $c, $cls, $nc, $ncls, $width);

	if ($length <= $pos) {
	    last;
	}
	$c = substr($spcstr, $pos, 1);
	$cls = $self->getlbclass($c);
	$clen = 1;

	# Hangul syllable block
	if ($cls == LB_H2 or $cls == LB_H3 or
	    $cls == LB_JL or $cls == LB_JV or $cls == LB_JT) {
	    while (1) {
		$pos++;
		last if $length <= $pos;
		$nc = substr($spcstr, $pos, 1);
		$ncls = $self->getlbclass($nc);
		if (($ncls == LB_H2 or $ncls == LB_H3 or
		    $ncls == LB_JL or $ncls == LB_JV or $ncls == LB_JT) and
		    $self->getlbrule($cls, $ncls) != DIRECT) {
		    $cls = $ncls;
		    $clen++;
		    next;
		}
		last;
	    } 
	    $width = EA_W;
	} else {
	    $pos++;
	    $width = &_bsearch(1, ord($c), EA_A, $self->{_ea_hash});
	}
	# After all, possible widths are non-spacing (z), wide (F/W) or
	# narrow (H/N/Na).

	if ($width == EA_z) {
	    $width = 0;
	} elsif ($width == EA_F or $width == EA_W) {
	    $width = 2;
	} else {
	    $width = 1;
	}
	if ($max and $max < $len + $width) {
	    $idx -= length $spc;
	    $idx = 0 unless 0 < $idx;
	    last;
	}
	$idx += $clen;
	$len += $width;
    }

    $max? $idx: $len;
}

sub _format {
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

sub _urgent_break {
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

sub _test_custom {
    my $self = shift;
    my $str = shift;
    my $posref = shift;
    my @custom = ();

    pos($str) = $$posref;
    foreach my $c (@{$self->{_custom_funcs}}) {
	my ($re, $func) = @{$c};
	if ($str =~ /$re/cg) {
	    my $frg = $1;
	    foreach my $b (&{$func}($self, $frg)) {
		my $s = '';
		while (length $b and
		       $self->getlbclass(substr($b, -1)) == LB_SP) {
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
    $$posref = pos($str);
    return @custom;
}

1;
