#-*- perl -*-

package Unicode::LineBreak;
require 5.008;

=encoding utf8

=head1 NAME

Unicode::LineBreak - UAX #14 Unicode Line Breaking Algorithm

=head1 SYNOPSIS

    use Unicode::LineBreak;
    $lb = Unicode::LineBreak->new();
    $broken = $lb->break($string);

=head1 DESCRIPTION

Unicode::LineBreak performs Line Breaking Algorithm described in
Unicode Standards Annex #14 [UAX #14].
East_Asian_Width informative properties defined by Annex #11 [UAX #11] will
be concerned to determin breaking positions.

=head2 Terminology

Following terms are used for convenience.

B<Mandatory break> is obligatory line breaking behavior defined by core
rules and performed regardless of surrounding characters.
B<Arbitrary break> is line breaking behavior allowed by core rules
and chosen by user to perform it.
Arabitrary break includes B<direct break> and B<indirect break>
defined by [UAX #14].

B<Alphabetic characters> are characters usually no line breaks are allowed
between pairs of them, except that other characters provide break
oppotunities.
B<Ideographic characters> are characters that usually allow line breaks
both before and after themselves.
[UAX #14] classifies most of alphabetic to AL and most of ideographic to ID.
These terms are inaccurate from the point of view by grammatology.

B<Number of columns> of a string is not always equal to the number of characters it contains:
Each of characters is either B<wide>, B<narrow> or non-spacing;
they occupy 2, 1 or 0 columns, respectively.
Several characters may be both wide and narrow by the contexts they are used.
Characters may have more various widths by customization.

=cut

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
    'DEFAULT' => \&_strwidth,
    'NARROWAL' => \&_strwidth,
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
	$idx = $self->_strwidth($len, $pre, $spc, $str, $self->{ColumnsMax})
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


=head2 Public Interface

=over 4

=item new ([KEY => VALUE, ...])

I<Constructor>.
About KEY => VALUE pairs see L</Options>.

=back

=cut

sub new {
    my $class = shift;

    my $self = { };
    &config($self, @_);
    bless $self, $class;
}

=over 4

=item $self->break (STRING)

I<Instance method>.
Break Unicode string STRING and returns it.

=back

=cut

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
    # $?_urg is a flag specifing $?_frg had been broken by urgent breaking.
    my ($b_cls, $b_frg, $b_spc, $b_urg) = (undef, '', '', 0);
    my ($a_cls, $a_frg, $a_spc, $a_urg);
    # Queue of urgent/custom broken fragments.
    my @custom = ();
    # Initially, "sot" event has not yet done and "sop" event is inhibited.
    my $sot_done = 0;
    my $sop_done = 1;

    my $pos = 0;
    my $str_len = length $str;
    while (1) {
	### Chop off a pair of unbreakable character clusters from text.

      CHARACTER_PAIR:
	while (1) {
	    my ($frg, $cls);

	    ($b_cls, $b_frg, $b_spc, $b_urg) = ($a_cls, $a_frg, $a_spc, $a_urg)
		if !defined $b_cls and defined $a_cls;
	    ($a_cls, $a_frg, $a_spc, $a_urg) = (undef, '', '', 0);
	    last CHARACTER_PAIR if defined $b_cls and $b_cls =~ /^eo/;

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
			$b_cls = 'eot';
			last CHARACTER_PAIR;
		    }
		    $frg = substr($str, $pos, 1);
		    $cls = $s->getlbclass($frg);

		    # - Explicit breaks and non-breaks

		    # LB7(1): × SP+
		    while ($cls == LB_SP) {
			$pos++;
			$b_spc .= $frg;
			$b_cls = LB_WJ # in case of (sot | BK etc.) × SP+
			    unless defined $b_cls;

			if ($str_len <= $pos) {
			    $b_cls = 'eot';
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
			$b_spc .= $frg; # $b_spc = SP* (BK etc.)
			$b_cls = 'eop';
			if ($pos < $str_len and $cls == LB_CR) {
			    $frg = substr($str, $pos, 1);
			    $cls = $s->getlbclass($frg);
			    if ($cls == LB_LF) {
				$pos++;
				$b_spc .= $frg;
			    }
			}

			# LB3: ! eot
			if ($str_len <= $pos) {
			    $b_cls = 'eot';
			}
			last CHARACTER_PAIR;
		    }

		    # - Explicit breaks and non-breaks

		    # LB7(2): × (SP* ZW+)+
		    if ($cls == LB_ZW) {
			while ($cls == LB_ZW) {
			    $pos++;
			    $b_frg .= $b_spc.$frg;
			    $b_spc = '';
			    $b_cls = LB_ZW;

			    if ($str_len <= $pos) {
				$b_cls = 'eot';
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
		$a_spc = '';
		$a_urg = 0;
		$pos++;
		$a_frg = $frg;
		$a_cls = $cls;

		# LB26, LB27: Treat
		#   (JL* H3 JT* | JL* H2 JV* JT* | JL* JV+ JT* | JL+ | JT+)
		# as if it were ID or, optionally, AL.
		# N.B. [UAX #14] allows some morbid "Korean syllable blocks"
		# such as
		#   JL CM JV JT
		# which might be broken to JL CM and rest.
		# cf. Unicode Standard section 3.12 `Conjoining Jamo Behavior'.
		if ($a_cls == LB_H2 or $a_cls == LB_H3 or
		    $a_cls == LB_JL or $a_cls == LB_JV or $a_cls == LB_JT) {
		    while ($pos < $str_len) {
			$frg = substr($str, $pos, 1);
			$cls = $s->getlbclass($frg);
			last unless
			    $a_cls == LB_JL and
			    ($cls == LB_JL or $cls == LB_JV or
			     $cls == LB_H2 or $cls == LB_H3) or
			    ($a_cls == LB_JV or $a_cls == LB_H2) and
			    ($cls == LB_JV or $cls == LB_JT) or
			    ($a_cls == LB_JT or $a_cls == LB_H3) and
			    $cls == LB_JT;
			$pos++;
			$a_frg .= $frg;
			$a_cls = $cls;
		    }
		    $a_cls = ($s->{HangulAsAL} eq 'YES')? LB_AL: LB_ID;
		}

		# - Combining marks

		# LB9: Treat X CM+ as if it were X
		# where X is anything except BK, CR, LF, NL, SP or ZW
		while ($pos < $str_len) {
		    $frg = substr($str, $pos, 1);
		    $cls = $s->getlbclass($frg);
		    last unless $cls == LB_CM;
		    $pos++;
		    $a_frg .= $frg;
		}		    

		# Legacy-CM: Treat SP CM+ as if it were ID.  cf. [UAX #14] 9.1.
		# LB10: Treat CM+ as if it were AL
		if ($a_cls == LB_CM) {
		    if ($s->{LegacyCM} eq 'YES' and
			defined $b_cls and length $b_spc and
			$s->getlbclass(substr($b_spc, -1)) == LB_SP) {
			$a_frg = substr($b_spc, -1).$a_frg;
			$a_cls = LB_ID;
			# clear ``before'' buffer if it was empty.
			$b_spc = substr($b_spc, 0, length($b_spc) - 1);
			$b_cls = undef unless length $b_frg or length $b_spc;
		    } else {
			$a_cls = LB_AL;
		    }
		}
	    } else {
		($a_cls, $a_frg, $a_spc, $a_urg) = @{shift @custom};
	    } # if (!scalar(@custom))

	    # - Start of text

	    # LB2: sot ×
	    last if defined $b_cls;
	} # CHARACTER_PAIR: while (1)

	## Determin line breaking action by classes of adjacent characters.
	## EOT is used only internally.

	my $action;
	# End of text.
	if ($b_cls eq 'eot') {
	    $action = EOT;
        # Mandatory break.
	} elsif ($b_cls eq 'eop') {
	    $action = MANDATORY;
	# Broken by urgent breaking or custom breaking.
	} elsif ($b_urg) {
	    $action = URGENT;
	# LB11 - LB29 and LB31: Tailorable rules (except LB11, LB12).
	} else {
	    $action = $s->getlbrule($b_cls, $a_cls);
	    # LB31: ALL ÷ ALL
	    $action ||= DIRECT;

	    # Check prohibited break.
	    if ($action == PROHIBITED or
		$action == INDIRECT and !length $b_spc) {

		# When conjunction of $b_frg and $a_frg is expected to exceed
		# CharactersMax, try urgent breaking.
		my $bsa = $b_frg.$b_spc.$a_frg;
		if ($s->{CharactersMax} < length $bsa) {
		    my @c = $s->_urgent_break(0, '', '', $a_cls, $bsa, $a_spc);
		    my @cc = ();

		    # When urgent break wasn't carried out and $b_frg was not
		    # longer than CharactersMax, break between $b_frg and
		    # $a_frg so that character clusters might not be broken.
		    if (scalar @c == 1 and $c[0]->[1] eq $bsa and
			length $b_frg <= $s->{CharactersMax}) {
			@cc = ([LB_XX, $b_frg, $b_spc, 1],
			       [$a_cls, $a_frg, $a_spc, 0]);
		    # Otherwise, if any of urgently broken fragments still
		    # exceed CharactersMax, force chop them.
		    } else {
			foreach my $c (@c) {
			    my ($cls, $frg, $spc, $urg) = @{$c};
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
				push @cc, [LB_XX, $b, '', 1] if length $b;
			    }
			    push @cc, [$cls, $frg, $spc, $urg];
			}
			# As $a_frg may be an imcomplete fragment,
			# urgent break won't be carried out at its end.
			$cc[$#cc]->[3] = 0 if scalar @cc;
		    }

		    # Shift back urgently broken fragments then retry.
		    unshift @custom, @cc;
		    if (scalar @custom) {
			($b_cls, $b_frg, $b_spc, $b_urg) = @{shift @custom};
			#XXX maybe eop/eot
		    } else {
			($b_cls, $b_frg, $b_spc, $b_urg) = (undef, '', '', 0);
		    }
		    next;
		} 
		# Otherwise, fragments may be conjuncted safely.  Read more.
		$b_frg .= $b_spc.$a_frg;
		$b_spc = $a_spc;
		$b_cls = $a_cls; #XXX maybe eop/eot
		next;
	    } # if ($action == PROHIBITED or ...)
	} # if ($b_cls eq 'eot')
	# After all, possible actions are EOT, MANDATORY and other arbitrary.

	### Examine line breaking action

	if (!$sot_done) {
	    # Process start of text.
	    $b_frg = $s->_break('sot', $b_frg);
	    $sot_done = 1;
	    $sop_done = 1;
	} elsif (!$sop_done) {
	    # Process start of paragraph.
	    $b_frg = $s->_break('sop', $b_frg);
	    $sop_done = 1;
	}
	
	# Check if arbitrary break is needed.
	my $l_newlen =
	    &{$s->{_sizing_func}}($s, $l_len, $l_frg, $l_spc, $b_frg);
	if ($s->{ColumnsMax} and $s->{ColumnsMax} < $l_newlen) {
	    $l_newlen = &{$s->{_sizing_func}}($s, 0, '', '', $b_frg); 

	    # When arbitrary break is expected to generate very short line,
	    # or when $b_frg will exceed ColumnsMax, try urgent breaking.
	    unless ($b_urg) {
		my @c = ();
		if ($l_len and $l_len < $s->{ColumnsMin}) {
		    @c = $s->_urgent_break($l_len, $l_frg, $l_spc,
					   $b_cls, $b_frg, $b_spc);
		} elsif ($s->{ColumnsMax} < $l_newlen) {
		    @c = $s->_urgent_break(0, '', '',
					   $b_cls, $b_frg, $b_spc);
		}
		if (scalar @c) {
		    push @c, [$a_cls, $a_frg, $a_spc, $a_urg]
			if defined $a_cls;
		    unshift @custom, @c;
		    if (scalar @custom) {
			($b_cls, $b_frg, $b_spc, $b_urg) = @{shift @custom};
			#XXX maybe eop/eot
		    } else {
			($b_cls, $b_frg, $b_spc, $b_urg) = (undef, '', '', 0);
		    }
		    next;
		}
	    }

	    # Otherwise, process arbitrary break.
	    if (length $l_frg.$l_spc) {
		$result .= $s->_break('', $l_frg);
		$result .= $s->_break('eol', $l_spc);
		my $bak = $b_frg;
		$b_frg = $s->_break('sol', $b_frg);
		$l_newlen = &{$s->{_sizing_func}}($s, 0, '', '', $b_frg)
		    unless $bak eq $b_frg;
	    }
	    $l_frg = $b_frg;
	    $l_len = $l_newlen;
	    $l_spc = $b_spc;
	# Arbitrary break is not needed.
	} else {
	    $l_frg .= $l_spc;
	    $l_frg .= $b_frg;
	    $l_len = $l_newlen;
	    $l_spc = $b_spc;
	} # if ($s->{ColumnsMax} and ...)

	# Mandatory break or end-of-text.
	if ($action == MANDATORY) {
	    # Process mandatory break.
	    $result .= $s->_break('', $l_frg);
	    $result .= $s->_break('eop', $l_spc);
	    $sop_done = 0;
	    $l_frg = '';
	    $l_len = 0;
	    $l_spc = '';
	} elsif ($action == EOT) {
	    # Process end of text.
	    $result .= $s->_break('', $l_frg);
	    $result .= $s->_break('eot', $l_spc);
	    last;
	}

	# Shift buffer.
	($b_cls, $b_frg, $b_spc, $b_urg) = ($a_cls, $a_frg, $a_spc, $a_urg);
    } # while (1)

    ## Return result.
    $result;
}


=over 4

=item $self->config (KEY)

=item $self->config (KEY => VALUE, ...)

I<Instance method>.
Get or update configuration.  About KEY => VALUE pairs see L</Options>.

=back

=cut

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
    my $v = $self->{'NSKanaAsID'};
    $v = $Config->{NSKanaAsID} unless defined $v;
    $v = 'ALL' if uc $v =~ m/^(YES|ALL)$/ or $v =~ /^\d/ and $v+0;
    my @v = ();
    push @v, 'ITERATION MARKS'          if $v eq 'ALL' or $v =~ /ITER/i;
    push @v, 'KANA SMALL LETTERS'       if $v eq 'ALL' or $v =~ /SMALL/i;
    push @v, 'PROLONGED SOUND MARKS'    if $v eq 'ALL' or $v =~ /LONG/i;
    push @v, 'MASU MARK'                if $v eq 'ALL' or $v =~ /MASU/i;
    $self->{'NSKanaAsID'} = join(',', @v) || 'NO';

    ## Customization of character properties.
    $self->{_custom_lb_map} = {
	LB_SAal() => LB_AL,
	LB_SAcm() => LB_CM,
	LB_SG() => LB_AL,
	LB_XX() => LB_AL,
	LB_AI() => ($self->{Context} eq 'EASTASIAN'? LB_ID: LB_AL),
	LB_NSidIter() => ($self->{NSKanaAsID} =~ /ITER/? LB_ID: LB_NS),
	LB_NSidKana() => ($self->{NSKanaAsID} =~ /SMALL/? LB_ID: LB_NS),
	LB_NSidLong() => ($self->{NSKanaAsID} =~ /LONG/? LB_ID: LB_NS),
	LB_NSidMasu() => ($self->{NSKanaAsID} =~ /MASU/? LB_ID: LB_NS),
    };
    $self->{_custom_ea_map} = {
	# Ambiguous (A) characters may be resolved to either
	# neutral (N) or fullwidth (F).
	EA_A() => ($self->{Context} ne 'EASTASIAN'? EA_N: EA_F),
	EA_AnLat() => ($self->{SizingMethod} eq 'NARROWAL' or
		       $self->{Context} ne 'EASTASIAN'? EA_N: EA_F),
	EA_AnGre() => ($self->{SizingMethod} eq 'NARROWAL' or
		       $self->{Context} ne 'EASTASIAN'? EA_N: EA_F),
	EA_AnCyr() => ($self->{SizingMethod} eq 'NARROWAL' or
		       $self->{Context} ne 'EASTASIAN'? EA_N: EA_F),
    };

    # Other options
    foreach $o (qw{CharactersMax ColumnsMin ColumnsMax Newline}) {
	$self->{$o} = $Config->{$o} unless defined $self->{$o};
    }
}


=over 4

=item getcontext ([Charset => CHARSET], [Language => LANGUAGE])

I<Function>.
Get language/region context used by character set CHARSET or
language LANGUAGE.

=back

=cut

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

=over 4

=item $self->getlbclass (STRING)

I<Instance method>.
Get line breaking property (class) of the first character of Unicode string
STRING.
Classes C<"AI">, C<"SA">, C<"SG"> and C<"XX"> will be resolved to other
appropriate classes. 

=back

=cut

sub getlbclass {
    my $self = shift;
    my $str = shift;
    return undef unless defined $str and length $str;

    my $cls = &_bsearch(0, ord($str));
    $cls = LB_XX unless defined $cls;
    my $c = $self->{_custom_lb_map}->{$cls};
    $cls = $c if defined $c;
    $cls;
}

=over 4

=item $self->getlbrule (BEFORE, AFTER)

I<Instance method>.
Get line breaking rule between class BEFORE and class AFTER.
One of following constants will be returned.

=over 4

=item C<MANDATORY>

Mandatory break.

=item C<DIRECT>

Both direct break and indirect break are allowed.

=item C<INDIRECT>

Indirect break is allowed, but direct break is prohibited.

=item C<PROHIBITED>

Prohibited break.

=back

B<Note>:
This method might not give appropriate value related to classes
C<"BK">, C<"CM">, C<"CR">, C<"LF">, C<"NL"> and C<"SP">,
and won't give meaningful value related to classes
C<"AI">, C<"SA">, C<"SG"> and C<"XX">. 

=back

=head2 Options

L</new> and L</config> methods accept following pairs.

=over 4

=item CharactersMax => NUMBER

Possible maximum number of characters in one line,
not counting trailing SPACEs and newline sequence.
Note that number of characters generally doesn't represent length of line.
Default is C<998>.

=item ColumnsMin => NUMBER

Minimum number of columns which line broken arbitrarily may include, not
counting trailing spaces and newline sequences.
Default is C<0>.

=item ColumnsMax => NUMBER

Maximum number of columns line may include not counting trailing spaces and
newline sequence.  In other words, maximum length of line.
Default is C<76>.

=back

See also L</UrgentBreaking> option and L</Customizing Line Breaking Behavior>.

=over 4

=item Context => CONTEXT

Specify language/region context.
Currently available contexts are C<"EASTASIAN"> and C<"NONEASTASIAN">.
Default context is C<"NONEASTASIAN">.

=item Format => METHOD

Specify the method to format broken lines.

=over 4

=item C<"DEFAULT">

Default method.
Just only insert newline at arbitrary breaking positions.

=item C<"NEWLINE">

Insert or replace newline sequences by that specified by L</Newline> option,
remove SPACEs leading newline sequences or end-of-text.  Then append newline
at end of text if it does not exist.

=item C<"TRIM">

Insert newline at arbitrary breaking positions. Remove SPACEs leading
newline sequences.

=item Subroutine reference

See L</"Customizing Line Breaking Behavior">.

=back

See also L</Newline> option.

=item HangulAsAL => C<"YES"> | C<"NO">

Treat hangul syllables and conjoining jamos as alphabetic characters (AL).
Default is C<"NO">.

=item LegacyCM => C<"YES"> | C<"NO">

Treat combining characters lead by a SPACE as an isolated combining character
(ID).
As of Unicode 5.0, such use of SPACE is not recommended.
Default is C<"YES">.

=item Newline => STRING

Unicode string to be used for newline sequence.
Default is C<"\n">.

=item NSKanaAsID => C<">CLASS...C<">

Treat some Nonstarters (NS) as normal ideographic characters (ID)
based on classification specified by CLASS.
CLASS may include following substrings.

=over 4

=item C<"ALL">

All of characters below.
Synonym is C<"YES">.

=item C<"ITERATION MARKS">

Ideographic iteration marks.
U+3005 IDEOGRAPHIC ITERATION MARK, U+303B VERTICAL IDEOGRAPHIC ITERATION MARK, U+309D HIRAGANA ITERATION MARK, U+309E HIRAGANA VOICED ITERATION MARK, U+30FD KATAKANA ITERATION MARK and U+30FE KATAKANA VOICED ITERATION MARK.

N.B. Some of them are neither hiragana nor katakana.

=item C<"KANA SMALL LETTERS">

=item C<"PROLONGED SOUND MARKS">

Hiragana or katakana small letters.

Hiragana or katakana prolonged sound marks.
U+30FC KATAKANA-HIRAGANA PROLONGED SOUND MARK and
U+FF70 HALFWIDTH KATAKANA-HIRAGANA PROLONGED SOUND MARK.

N.B. These letters are optionally treated either as Nonstarter or
as normal ideographic.  See [JIS X 4051] 6.1.1.

=item C<"MASU MARK">

U+303C MASU MARK.

N.B. Although this character is not kana, it is usually regarded as
abbreviation to sequence of hiragana C<"ます"> or katakana C<"マス">,
MA and SU.

N.B. This character is classified as Nonstarter (NS) by [UAX #14]
and as Class 13 (corresponding to ID) by [JIS X 4051].

=item C<"NO">

Default.
None of above are treated as ID characters.

=back

=item SizingMethod => METHOD

Specify method to calculate size of string.
Following options are available.

=over 4

=item C<"DEFAULT">

Default method.

=item C<"NARROWAL">

Some particular letters of Latin, Greek and Cyrillic scripts have ambiguous
(A) East_Asian_Width property.  Thus, these characters are treated as wide
in C<"EASTASIAN"> context.
By this option those characters are always treated as narrow.

=item Subroutine reference

See L</"Customizing Line Breaking Behavior">.

=back

=item UrgentBreaking => METHOD

Specify method to handle excessing lines.
Following options are available.

=over 4

=item C<"CROAK">

Print error message and die.

=item C<"FORCE">

Force breaking excessing fragment.

=item C<"NONBREAK">

Default method.
Won't break excessing fragment.

=item Subroutine reference

See L</Customizing Line Breaking Behavior>.

=back

=item UserBreaking => C<[>METHOD, ...C<]>

Specify user-defined line breaking behavior(s).
Following methods are available.

=over 4

=item C<"NONBREAKURI">

Won't break URIs.
Currently HTTP(S) and (S)FTP(S) URIs are supported.

=item C<"BREAKURI">

Break URIs at the positions before SOLIDUSes (slashes).
By default, URIs are broken at the positions I<after> SOLIDUSes.

=item C<[> REGEX, SUBREF C<]>

The sequences matching regular expression REGEX will be broken by
subroutine referred by SUBREF.
For more details see L</Customizing Line Breaking Behavior>.

=back

=back

=head2 Constants

=over 4

=item C<LB_I<??>>

Index values to specify 36 line breaking properties (classes)
defined in [UAX #14].

=item C<@LB_CLASSES>

An array of all classes above.

=item C<MANDATORY>, C<DIRECT>, C<INDIRECT>, C<PROHIBITED>

4 values to specify line breaking behaviors.

=item C<$UNICODE_VERSION>

A string to specify version of Unicode standard this module refers.

=back

=head2 Customizing Line Breaking Behavior

=head3 Formatting Lines

If you specify subroutine reference as a value of L</Format> option,
it should accept three arguments:

    MODIFIED = &subroutine(SELF, EVENT, STR);

SELF is an instance of LineBreak object,
EVENT is a string to determine the context that subroutine was called in,
and STR is a fragment of Unicode string leading or trailing breaking position.

    EVENT |When Fired           |Value of STR
    -----------------------------------------------------------------
    "sot" |Beginning of text    |Fragment of first line
    "sop" |After mandatory break|Fragment of next line
    "sol" |After arbitrary break|Fragment on sequel of line
    ""    |Just before any      |Complete line without trailing
          |breaks               |SPACEs
    "eol" |Arabitrary break     |SPACEs leading breaking position
    "eop" |Mandatory break      |Newline and its leading SPACEs
    "eot" |End of text          |SPACEs (and newline) at end of
          |                     |text
    -----------------------------------------------------------------

Subroutine should return modified text fragment or may return
C<undef> to express that no modification occurred.
Note that modification in the context of C<"sot">, C<"sop"> or C<"sol"> may
affect decision of successive breaking positions while in the others won't.

=cut

sub _break {
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

=head3 User-Defined Breaking Behaviors

When a line generated by arbitrary break is expected to be beyond measure of
either CharactersMax, ColumnsMin or ColumnsMax, B<urgent break> may be
performed on successive string.
If you specify subroutine reference as a value of L</UrgentBreaking> option,
it should accept five arguments:

    BROKEN = &subroutine(SELF, LEN, PRE, SPC, STR);

SELF is an instance of LineBreak object, LEN is size of preceding string,
PRE is preceding Unicode string, SPC is additional SPACEs and STR is a
Unicode string to be broken.

Subroutine should return an array of broken string STR.

If you specify [REGEX, SUBREF] array reference as an item of
L</UserBreaking> option,
subroutine should accept two arguments:

    BROKEN = &subroutine(SELF, STR);

SELF is an instance of LineBreak object and
STR is a Unicode string matched with REGEX.

Subroutine should return an array of broken string STR.

=cut

sub _urgent_break {
    my $self = shift;
    my $l_len = shift;
    my $l_frg = shift;
    my $l_spc = shift;
    my $cls = shift;
    my $frg = shift;
    my $spc = shift;

    if (ref $self->{_urgent_breaking_func}) {
	my @broken = map { [LB_XX, $_, '', 1]; }
	&{$self->{_urgent_breaking_func}}($self, $l_len, $l_frg, $l_spc, $frg);
	$broken[$#broken]->[0] = $cls;
	$broken[$#broken]->[2] = $spc;
	return @broken;
    }
    return ([$cls, $frg, $spc, 1]);
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
		    push @custom, [LB_XX, $b, $s, 1];
		} elsif (scalar @custom) {
		    $custom[$#custom]->[2] .= $s;
		} elsif (length $s) {
		    push @custom, [LB_XX, $b, $s, 1];
		}
	    }
	    last;
	}
    }
    $$posref = pos($str);
    return @custom;
}


=head3 Calculating String Size

If you specify subroutine reference as a value of L</SizingMethod> option,
it will be called with five or six arguments:

    COLS = &subroutine(SELF, LEN, PRE, SPC, STR);

    CHARS = &subroutine(SELF, LEN, PRE, SPC, STR, MAX);

SELF is an instance of LineBreak object, LEN is size of preceding string,
PRE is preceding Unicode string, SPC is additional SPACEs and STR is a
Unicode string to be processed.

By the first format, subroutine should return calculated number of columns of C<PRE.SPC.STR>.
The number of columns may not be an integer: Unit of the number may be freely chosen, however, it should be same as those of L</ColumnsMin> and L</ColumnsMax> option.

By the second format, subroutine should return maximum
I<number of Unicode characters> that substring of STR contains
by which number of columns PRE.SPC.SUBSTR contains may not exceed MAX.
This format will be used when L<UrgentBreaking> is set to C<"FORCE">.
If you don't wish to implement latter format, C<undef> should be returned.

=cut

# self->_strwidth(LEN, PRE, SPC, STR)
# self->_strwidth(LEN, PRE, SPC, STR, MAX)
sub _strwidth {
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

    my $narrowal;
    if (!ref $self->{SizingMethod} and
	$self->{SizingMethod} eq 'NARROWAL') {
	$narrowal = 1;
    } else {
	$narrowal = 0;
    }

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
		last unless
		    $cls == LB_JL and
		    ($ncls == LB_JL or $ncls == LB_JV or
		     $ncls == LB_H2 or $ncls == LB_H3) or
		    ($cls == LB_JV or $cls == LB_H2) and
		    ($ncls == LB_JV or $ncls == LB_JT) or
		    ($cls == LB_H3 or $cls == LB_JT) and
		    $ncls == LB_JT;
		$cls = $ncls;
		$clen++;
	    } 
	    $width = EA_W;
	} else {
	    $pos++;
	    $width = &_bsearch(1, ord($c));
	    $width = EA_A unless defined $width;
	    my $w = $self->{_custom_ea_map}->{$width};
	    $width = $w if defined $w;
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

=head3 Character Classifications and Core Line Breaking Rules

Classifications of character and core line breaking rules are defined by
L<Unicode::LineBreak::Data> and L<Unicode::LineBreak::Rules>.
If you wish to customize them, see F<data> directory of source package.

=head3 Configuration File

Built-in defaults of option parameters for L</new> and L</config> method
can be overridden by configuration files:
F<Unicode/LineBreak/Defaults.pm>.
For more details read F<Unicode/LineBreak/Defaults.pm.sample>.

=head2 Conformance to Standards

Character properties this module is base on are defined by
Unicode Standards version 5.1.0.

This module is intended to implement UAX14-C2.

=over 4

=item *

Some ideographic characters may be treated either as NS or as ID by choice.

=item *

Hangul syllables and conjoining jamos may be treated as
either ID or AL by choice.

=item *

Characters assigned to AI may be resolved to either AL or ID by choice.

=item *

Character(s) assigned to CB are not resolved.

=item *

Characters assigned to SA are resolved to AL,
except that characters that have General_Category Mn or Mc be resolved to CM.

=item *

Characters assigned to SG or XX are resolved to AL.

=back

=head1 BUGS

Please report bugs or buggy behaviors to developer.  See L</AUTHOR>.

=head1 VERSION

See L<Unicode::LineBreak::Version>.

Development versions of this module may be found at 
L<http://hatuka.nezumi.nu/repos/Unicode-LineBreak/>.

=head1 REFERENCES

=over 4

=item [JIS X 4051]

JIS X 4051:2004
I<日本語文書の組版方法> (I<Formatting Rules for Japanese Documents>),
published by Japanese Standards Association, 2004.

=item [UAX #11]

A. Freytag (2008).
I<Unicode Standard Annex #11: East Asian Width>, Revision 17.
L<http://unicode.org/reports/tr11/>.

=item [UAX #14]

A. Freytag and A. Heninger (2008).
I<Unicode Standard Annex #14: Unicode Line Breaking Algorithm>, Revision 22.
L<http://unicode.org/reports/tr14/>.

=back

=head1 SEE ALSO

L<Text::LineFold>, L<Text::Wrap>.

=head1 AUTHOR

Copyright (C) 2009 Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>.

This program is free software; you can redistribute it and/or modify it 
under the same terms as Perl itself.

=cut

1;
