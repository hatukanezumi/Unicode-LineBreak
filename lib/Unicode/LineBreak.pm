#-*- perl -*-

package Unicode::LineBreak;
require 5.008;

### Pragmas:
use strict;
use warnings;
use vars qw($VERSION @EXPORT_OK @ISA $Config);

### Exporting:
use Exporter;
our @EXPORT_OK = qw(UNICODE_VERSION context);
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);

### Inheritance:
our @ISA = qw(Exporter);

### Other modules:
use Carp qw(croak carp);
use Encode qw(is_utf8);
use MIME::Charset;
use Unicode::GCString;

### Globals

### The package version
require Unicode::LineBreak::Version;

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
use constant 1.01;
my $package = __PACKAGE__;
my @consts = grep { s/^${package}::(\w\w+)$/$1/ } keys %constant::declared;
push @EXPORT_OK, @consts;
push @{$EXPORT_TAGS{'all'}}, @consts;

### Load XS module
require XSLoader;
XSLoader::load('Unicode::LineBreak', $VERSION);

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
	return $_[2].$_[0]->config('Newline') if $_[1] eq 'eol';
	undef;
    },
    'NEWLINE' => sub {
	return $_[0]->config('Newline') if $_[1] =~ /^eo/;
	undef;
    },
    'TRIM' => sub {
	my $self = shift;
	my $event = shift;
	my $str = shift;
	if ($event eq 'eol') {
	    return $self->config('Newline');
	} elsif ($event =~ /^eo/) {
	    $str = $str->substr(1)
		while $str->length and $str->lbclass(0) == LB_SP;
	    return $str;
	}
	undef;
    },
);

# Built-in behavior by L</SizingMethod> options.
my %SIZING_FUNCS = (
    'DEFAULT' => undef,
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

    my $max = $self->config('ColumnsMax') || 0;
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
my $URIre = qr{
	       \b
	       (?:url:)?
	       (?:[a-z][-0-9a-z+.]+://|news:|mailto:)
	       [\x21-\x7E]+
}iox;
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
			    (?<=^url:) |
			    (?<=[/]) (?=[^/]) |
			    (?<=[^-.]) (?=[-~.,_?\#%=&]) |
			    (?<=[=&]) (?=.)
			}iox, $_[1];
			# Won't break punctuations at end of matches.
			while (2 <= scalar @c and $c[$#c] =~ /^[.:;,>]+$/) {
			    my $c = pop @c;
			    $c[$#c] .= $c;
			}
			@c;
		    }],
);

use overload
    '%{}' => \&as_hashref;

sub new {
    my $class = shift;

    my $self = __PACKAGE__->_new();
    $self->config((%$Config));
    $self->config(@_);
    $self;
}

sub break ($$) {
    my $self = shift;
    my $str = shift;
    return '' unless defined $str and length $str;
    my $result = '';

    while (1000 < length $str) {
	my $s = substr($str, 0, 1000);
	$str = substr($str, 1000);
	$result .= $self->break_partial($s);
    }
    $result .= $self->break_partial($str);
    return $result . $self->break_partial(undef);
}

sub break_partial ($$) {
    my $s = shift;
    my $str = shift;
    my $eot = 0;

    $eot = !(defined $str);

    ## Unread and additional input.
    $str = $s->_break_partial($str);

    # Constant.
    my $null = Unicode::GCString->new('', $s);

    ### Initialize status.
    ## Line buffer.
    # _frg: Unbreakable text fragment.
    # _spc: Trailing spaces.
    # _cols: Number of columns of _frg: can be differ from _frg->columns.
    my $line_frg = $s->attr('_unwritten_frg');
    my $line_spc = $s->attr('_unwritten_spc');
    my $line_cols = $s->attr('_unwritten_cols');
    ## ``before'' and ``after'' buffers.
    # cls: Line breaking class.
    # frg: Unbreakable text fragment.
    # spc: Trailing spaces.
    # eop: There is a mandatory breaking point at end of this buffer.
    my %before = ('frg' => $null, 'spc' => $null);
    my %after = ('frg' => $null, 'spc' => $null);
    ## Start of text/paragraph status.
    # 0: Start of text not done.
    # 1: Start of text done while start of paragraph not done.
    # 2: Start of paragraph done.
    my $sox = $s->attr('_sox');

    ## Result.
    my $result = '';
    ## End of substring broken by urgent breaking.
    my $urg_end = 0;

    while (1) {
	### Chop off a pair of unbreakable character clusters from text.

      CHARACTER_PAIR:
	while (1) {
	    my $gcls;

	    # End of input.
	    last CHARACTER_PAIR if $str->eot;
	    # Mandatory break
	    last CHARACTER_PAIR if defined $before{cls} and $before{eop};

	    if (1) {
		## Then, go ahead reading input.

		$gcls = $str->lbclass;

		#
		# Append SP/ZW/eop to ``before'' buffer.
		#
		while (1) {
		    # - Explicit breaks and non-breaks

		    # LB7(1): × SP+
		    if ($gcls == LB_SP) {
			$before{spc} .= $str->next;
			# Treat (sot | eop) SP+  as if it were WJ.
			$before{cls} = LB_WJ unless defined $before{cls};

			# End of input.
			last CHARACTER_PAIR if $str->eot;
			$gcls = $str->lbclass;
		    }

		    # - Mandatory breaks

		    # LB4 - LB7: × SP* (BK | CR LF | CR | LF | NL) !
		    if ($gcls == LB_BK or $gcls == LB_CR or $gcls == LB_LF or
			$gcls == LB_NL) {
			$before{spc} .= $str->next;
			$before{cls} = $gcls;
			$before{eop} = 1
			    unless !$eot and $gcls == LB_CR and $str->eot;
			last CHARACTER_PAIR;
		    }

		    # - Explicit breaks and non-breaks

		    # LB7(2): × (SP* ZW+)+
		    if ($gcls == LB_ZW) {
			$before{frg} .= $before{spc}.($str->next);
			$before{spc} = $null;
			$before{cls} = $gcls;

			# End of input
			last CHARACTER_PAIR if $str->eot;
			$gcls = $str->lbclass;
			next;
		    }
		    last;
		} # while (1)

		#
		# Then fill ``after'' buffer.
		#

		# - Rules for other line breaking classes

		# LB1: Assign a line breaking class to each characters.
		%after = ('frg' => $str->next, 'spc' => $null);

		# - Combining marks  
		# LB9: Treat X CM+ as if it were X  
		# where X is anything except BK, CR, LF, NL, SP or ZW  
		# (NB: Some CM characters may be single grapheme cluster
		# since they have Grapheme_Cluster_Break property Control.)
		while (!$str->eot) {  
		    last unless $str->lbclass eq LB_CM;
		    $after{frg} .= $str->next;
		}
		# Legacy-CM: Treat SP CM+ as if it were ID.  cf. [UAX #14] 9.1.
		# LB10: Treat any remaining CM+ as if it were AL.
		if ($gcls == LB_CM) {
		    if ($s->config('LegacyCM') and
			defined $before{cls} and $before{spc}->length and
			$before{spc}->substr(-1)->lbclass == LB_SP) {
			$after{frg} = $before{spc}->substr(-1).$after{frg};
			$after{cls} = LB_ID;

			# clear ``before'' buffer if it was empty.
			$before{spc} =
			    $before{spc}->substr(0, -1);
			$before{cls} = undef
			    unless $before{frg}->length or
			    $before{spc}->length;
		    } else {
			$after{cls} = LB_AL;
		    }
		# LB27: Treat hangul syllable as if it were ID (or AL).
		} elsif ($gcls == LB_H2 or $gcls == LB_H3 or
			 $gcls == LB_JL or $gcls == LB_JV or $gcls == LB_JT) {
		    $after{cls} =
			$s->config('HangulAsAL')? LB_AL: LB_ID;
		} else {
		    $after{cls} = $gcls;
		}
	    } # if (1)

	    # - Start of text

	    # LB2: sot ×
	    last if defined $before{cls};

	    # shift buffers.
	    %before = (%after);
	    %after = ('frg' => $null, 'spc' => $null);
	} # CHARACTER_PAIR: while (1)

	## Determin line breaking action by classes of adjacent characters.

	my $action;

	# Mandatory break.
	if ($before{eop}) {
	    $action = MANDATORY;
	# LB11 - LB29 and LB31: Tailorable rules (except LB11, LB12).
        # Or custom/complex breaking.
	} elsif (defined $after{cls}) {
	    if ($after{frg}->flag(0) & BREAK_BEFORE) {
		$action = DIRECT;
	    } elsif ($after{frg}->flag(0) & PROHIBIT_BEFORE) {
		$action = PROHIBITED;
	    } else {
		$action = $s->lbrule($before{cls}, $after{cls});
	    }

	    # Check prohibited break.
	    if ($action == PROHIBITED or
		($action == INDIRECT and $before{spc}->length == 0)) {

		# When conjunction of $before{frg} and $after{frg} is
		# expected to exceed CharactersMax, try urgent breaking.
		my $bsa = $before{frg}.$before{spc}.$after{frg};
		if ($s->config('CharactersMax') < $bsa->chars) {
		    my @c = $s->_urgent_break(0, '', '', $after{cls},
					      $bsa, $after{spc});
		    my $broken = $null;
		    foreach my $c (@c) {
			$c->flag(0, BREAK_BEFORE);
			my $max = $s->config('CharactersMax');
			# If any of urgently broken fragments still
			# exceed CharactersMax, force chop them.
			if ($max and $max < $c->chars) {
			    while ($max < $c->chars and
				   $s->lbclass(substr($c->as_string, $max))
				   == LB_CM) {
				$max++;
			    }
			    my $substr = substr("$c", 0, $max); #FIXME:
			    my $brk = Unicode::GCString->new($substr, $s);
			    $c->flag($brk->length, BREAK_BEFORE);
			}
			$broken .= $c;
		    }
		    my $l = ($bsa.$after{spc})->length;
		    my $newpos = $str->pos - $l;
		    $urg_end = $str->pos;
		    $str->substr($newpos, $l, $broken);
		    $str->pos($newpos);
		    %before = ('frg' => $null, 'spc' => $null);
		    %after = ('frg' => $null, 'spc' => $null);
		    next;
		} 
		# Otherwise, fragments may be conjuncted safely.  Read more.
		my $frg = $before{frg}.$before{spc}.$after{frg};
		%before = (%after); $before{frg} = $frg;
		%after = ('frg' => $null, 'spc' => $null);
		next;
	    } # if ($action == PROHIBITED or ...)
	} # if ($before{eop})

        # Check end of input.
        if (!$eot and !defined $after{cls} and $str->eot) {
	    # Save status then output partial result.
	    $s->attr('_unwritten_frg' => $line_frg);
	    $s->attr('_unwritten_spc' => $line_spc);
	    $s->attr('_unwritten_cols' => $line_cols);
	    $s->attr('_unread' => $before{frg}.$before{spc});
	    $s->attr('_sox' => $sox);
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
	my $newcols = $s->_sizing($line_cols, $line_frg, $line_spc,
				  $before{frg});
	if ($s->config('ColumnsMax') and $s->config('ColumnsMax') < $newcols) {
	    $newcols = $s->_sizing(0, '', '', $before{frg}); 

	    # When arbitrary break is expected to generate very short line,
	    # or when $before{frg} will exceed ColumnsMax, try urgent breaking.
	    if ($urg_end < $str->pos - ($after{frg}.$after{spc})->length) {
		my @c = ();
		if ($line_cols and $line_cols < $s->config('ColumnsMin')) {
		    @c = $s->_urgent_break($line_cols, $line_frg, $line_spc,
					   $before{cls}, $before{frg},
					   $before{spc});
		} elsif ($s->config('ColumnsMax') < $newcols) {
		    @c = $s->_urgent_break(0, '', '',
					   $before{cls}, $before{frg},
					   $before{spc});
		}
		if (scalar @c) {
		    my $broken = $null;
		    foreach my $c (@c) {
			$c->flag(0, BREAK_BEFORE) unless $c->flag(0);
			$broken .= $c;
		    }
		    my $blen = ($before{frg}.$before{spc})->length;
		    my $alen = ($after{frg}.$after{spc})->length;
		    my $newpos = $str->pos - ($blen + $alen);
		    $urg_end = $newpos + $broken->length;
		    $str->substr($newpos, $blen, $broken);
		    $str->pos($newpos);
		    %before = ('frg' => $null, 'spc' => $null);
		    %after = ('frg' => $null, 'spc' => $null);
		    next;
		}
	    }

	    # Otherwise, process arbitrary break.
	    if (length $line_frg or length $line_spc) {
		$result .= $s->_format('', $line_frg)->as_string;
		$result .= $s->_format('eol', $line_spc)->as_string;
		my $bak = $before{frg};
		$before{frg} = $s->_format('sol', $before{frg});
		$newcols = $s->_sizing(0, '', '', $before{frg})
		    unless $bak eq $before{frg};
	    }
	    $line_frg = $before{frg};
	    $line_spc = $before{spc};
	    $line_cols = $newcols;
	# Arbitrary break is not needed.
	} else {
	    $line_frg = $line_frg.$line_spc.$before{frg};
	    $line_spc = $before{spc};
	    $line_cols = $newcols;
	} # if ($s->config('ColumnsMax') and ...)

	# Mandatory break or end-of-text.
	if ($eot and !defined $after{cls} and $str->eot) {
	    last;
	}
	if ($action == MANDATORY) {
	    # Process mandatory break.
	    $result .= $s->_format('', $line_frg)->as_string;
	    $result .= $s->_format('eop', $line_spc)->as_string;
	    $sox = 1; # eop done then sop must be carried out.
	    $line_frg = '';
	    $line_spc = '';
	    $line_cols = 0;
	}

	# Shift buffers.
	%before = (%after);
	%after = ('frg' => $null, 'spc' => $null);
    } # TEXT: while (1)

    # Process end of text.
    $result .= $s->_format('', $line_frg)->as_string;
    $result .= $s->_format('eot', $line_spc)->as_string;

    ## Reset status then return the rest of result.
    $s->_reset;
    $result;
}

sub preprocess ($$$) {
    my $self = shift;
    my $user_funcs = shift;
    my $str = shift;

    if (ref $str) {
	$str = $str->as_string;
    }
    unless (defined $str and length $str) {
	$str = '';
    }

    my $ret = Unicode::GCString->new('', $self);
    while (length $str) {
	my $func;
	my ($s, $match, $post) = ($str, '', '');
	foreach my $ub (@{$user_funcs}) {
	    my ($re, $fn) = @{$ub};
	    if ($str =~ /$re/) {
		if (length $& and length $` < length $s) { #`
		    ($s, $match, $post) = ($`, $&, $'); #'`
		    $func = $fn;
		}
	    }
	}
	if (length $match) {
	    $str = $post;
	} else {
	    $s = $str;
	    $str = '';
	}

	$ret .= $s if length $s;

	# Break matched fragment.
	if (length $match) {
	    my $first = 1;
	    foreach my $s (&{$func}($self, $match)) {
		$s = Unicode::GCString->new($s, $self);
		my $length = $s->length;
		if ($length) {
		    if (!$first) {
			$s->flag(0, BREAK_BEFORE);
		    }
		    for (my $i = 1; $i < $length; $i++) {
			$s->flag($i, PROHIBIT_BEFORE);
		    }
		    $ret .= $s;
		}
		$first = 0;
	    }
	}
    }

    $ret;
}

sub config ($@) {
    my $self = shift;
    my @nopts = qw(CharactersMax ColumnsMin ColumnsMax Context
		   HangulAsAL LegacyCM Newline);
    my @uopts = qw(Format SizingMethod
		   TailorEA TailorLB UrgentBreaking UserBreaking);
    my %nopts = map { (uc $_ => $_); } @nopts;
    my %uopts = map { (uc $_ => $_); } @uopts;

    # Get config.
    if (scalar @_ == 1) {
	my $k = shift;
	if ($uopts{uc $k}) {
	    return $self->{$uopts{uc $k}};
	} else {
	    return $self->_config($nopts{uc $k} || $k);
	}
    }

    # Set config.
    my %params = @_;
    my %copts = ();
    my %config = ();
    my $k;
    foreach $k (keys %params) {
	my $v = $params{$k};
	if ($uopts{uc $k}) {
	    $self->{$uopts{uc $k}} = $v;
	    $copts{$uopts{uc $k}} = $v;
	} else {
	    $config{$nopts{uc $k} || $k} = $v;
	}
    }

    ## Utility options.
    # Format method.
    if (defined $copts{Format}) {
	if (ref $copts{Format} eq 'CODE') {
	    $config{Format} = $copts{Format};
	} else {
	    $config{Format} =
		$FORMAT_FUNCS{uc $copts{Format}} ||
		$FORMAT_FUNCS{'DEFAULT'};
	}
    }
    # Sizing method
    if (defined $copts{SizingMethod}) {
	if (ref $copts{SizingMethod} eq 'CODE') {
	    $config{SizingMethod} = $copts{SizingMethod};
	} else {
	    $config{SizingMethod} =
		$SIZING_FUNCS{uc $copts{SizingMethod}} ||
		$SIZING_FUNCS{'DEFAULT'};
	}
    }
    # Urgent break
    if (defined $copts{UrgentBreaking}) {
	if (ref $copts{UrgentBreaking} eq 'CODE') {
	    $config{UrgentBreaking} = $copts{UrgentBreaking};
	} else {
	    $config{UrgentBreaking} =
		$URGENT_BREAKING_FUNCS{uc $copts{UrgentBreaking}} || undef;
	}
    }
    # Custom break
    if (defined $copts{UserBreaking}) {
	$copts{UserBreaking} = [$copts{UserBreaking}]
	    unless ref $copts{UserBreaking} eq 'ARRAY';
	my @cf = ();
	foreach my $ub (@{$self->{UserBreaking}}) {
	    next unless defined $ub;
	    unless (ref $ub eq 'ARRAY') {
		$ub = $USER_BREAKING_FUNCS{uc $ub};
		next unless defined $ub;
	    }
	    my ($re, $func) = @{$ub};
	    push @cf, [qr{$re}o, $func];
	}
	$config{UserBreaking} = \@cf;
    }
    # Character classes
    if (defined $copts{TailorLB} or defined $copts{TailorEA}) {
	$copts{TailorLB} ||= $self->{TailorLB};
	$copts{TailorEA} ||= $self->{TailorEA};
	my %map = ();
	foreach my $o (qw{TailorLB TailorEA}) {
	    $copts{$o} = [@{$Config->{$o}}]
		unless defined $copts{$o} and ref $copts{$o} eq 'ARRAY';
	    my @v = @{$copts{$o}};
	    while (scalar @v) {
		my $k = shift @v;
		my $v = shift @v;
		next unless defined $k and defined $v;
		if (ref $k eq 'ARRAY') {
		    foreach my $c (@{$k}) {
			$map{$c} ||= [-1, -1];
			if ($o eq 'TailorLB') {
			    $map{$c}->[0] = $v;
			} else {
			    $map{$c}->[1] = $v;
			}
		    }
		} else {
		    $map{$k} ||= [-1, -1];
		    if ($o eq 'TailorLB') {
			$map{$k}->[0] = $v;
		    } else {
			$map{$k}->[1] = $v;
		    }
		}
	    }
	}
	my @map = ();
	my ($beg, $end) = (undef, undef);
	my $p;
	foreach my $c (sort {$a <=> $b} keys %map) {
	    unless ($map{$c}) {
		next;
	    } elsif (defined $end and $end + 1 == $c and
		     $p->[0] == $map{$c}->[0] and $p->[1] == $map{$c}->[1]) {
		$end = $c;
	    } else {
		if (defined $beg and defined $end) {
		    push @map, [$beg, $end, @{$p}];
		}
		$beg = $end = $c;
		$p = $map{$c};
	    }
	}
	if (defined $beg and defined $end) {
	    push @map, [$beg, $end, @{$p}];
	}
	$config{_map} = \@map;
    }

    $self->_config((%config)) if scalar keys %config;
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

=begin comment

sub _urgent_break ($$$$$$$) {
    my $self = shift;
    my $l_len = shift;
    my $l_frg = shift;
    my $l_spc = shift;
    my $cls = shift;
    my $frg = shift;
    my $spc = shift;

    if (ref $self->config('_urgent_breaking_func')) {
	my @broken = map
	{ $_ = Unicode::GCString->new($_, $self) unless ref $_; $_ }
	&{$self->config('_urgent_breaking_func')}($self, $l_len, $l_frg, $l_spc, $frg);
	if (scalar @broken) {
	    $broken[$#broken] .= $spc;
	} else {
	    @broken = ($frg.$spc);
	}
	return @broken;
    }

    return ($frg.$spc);
}

=end comment

=cut

1;
