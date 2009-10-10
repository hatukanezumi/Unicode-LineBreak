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
    my $sizing = $self->{SizingMethod};
    unless (ref $sizing eq 'CODE') {
	if ($sizing) {
	    $sizing = $SIZING_FUNCS{$sizing};
	}
 	$sizing ||= \&strsize;
    }
    my @result = ();

    while (1) {
        my $idx = &{$sizing}($self, $len, $pre, $spc, $str, $max);
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
    '%{}' => \&as_hashref,
    '${}' => \&as_scalarref,
    '""' => \&as_string,
    ;

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


sub lbclass_custom {
    my $self = shift;
    my $str = shift;
    my $base = shift;
    my $lbc;

    # LB9: Treat X CM+ as if it were X  
    # where X is anything except BK, CR, LF, NL, SP or ZW  
    $lbc = $str->lbclass($base);
    # LB10: Treat any remaining CM+ as if it were AL.
    if ($lbc == LB_CM) {
	$lbc = LB_AL;
    # LB27: Treat hangul syllable as if it were ID (or AL).
    } elsif ($lbc == LB_H2 or $lbc == LB_H3 or
	     $lbc == LB_JL or $lbc == LB_JV or $lbc == LB_JT) {
	$lbc = $self->config('HangulAsAL')? LB_AL: LB_ID;
    }
    $lbc;
}

sub break_partial ($$) {
    my $s = shift;
    my $str = shift;
    my $eot = 0;

    $eot = !(defined $str);

    ## Unread and additional input.
    $str = $s->_break_partial($str);
    $str->pos(0);

    # Constant.
    my $null = Unicode::GCString->new('', $s);

    ### Initialize status.

    ## Line buffer.
    # bufStr: Unbreakable text fragment.
    # bufSpc: Trailing spaces.
    # bufCols: Number of columns of befStr: can be differ from bufStr->columns.
    # State: Start of text/paragraph status.
    # 0: Start of text not done.
    # 1: Start of text done while start of paragraph not done.
    # 2: Start of paragraph done while end of paragraph not done.
    my $state = $s->attr('state');
    my $bufStr = $s->attr('bufstr');
    my $bufSpc = $s->attr('bufspc');
    my $bufCols = $s->attr('bufcols');

    ## Indexes and flags
    # bBeg:  Start of unbreakable text fragment.
    # bLen:  Length of unbreakable text fragment.
    # bSpc:  Length of trailing spaces.
    # urgEnd: End of substring broken by urgent breaking.
    #
    # ...read...| before :CM |  spaces  | after :CM |...unread...|
    #           ^       ->bCM<-         ^      ->aCM<-           ^
    #           |<-- bLen -->|<- bSpc ->|           ^            |
    #          bBeg                 candidate    str->pos     end of
    #                                breaking                  input
    #                                 point
    # `read' positions shall never be read more.
    #
    my ($bBeg, $bLen, $bCM, $bSpc, $aCM) = (0, 0, 0, 0, 0);
    my $urgEnd = 0;

    ## Result.
    my $result = '';

    while (1) {
	### Chop off a pair of unbreakable character clusters from text.

      CHARACTER_PAIR:
	while (!$str->eos) {
	    my $lbc;

	    if (1) {
		## Go ahead reading input.

		$lbc = $str->lbclass;

		#
		# Append SP/ZW/eop to ``before'' buffer.
		#
		while (1) {
		    # - Explicit breaks and non-breaks

		    # LB7(1): × SP+
		    if ($lbc == LB_SP) {
			$str->next;
			$bSpc++;

			# End of input.
			last CHARACTER_PAIR if $str->eos;
			$lbc = $str->lbclass;
		    }

		    # - Mandatory breaks

		    # LB4 - LB7: × SP* (BK | CR LF | CR | LF | NL) !
		    if ($lbc == LB_BK or $lbc == LB_CR or $lbc == LB_LF or
			$lbc == LB_NL) {
			$str->next;
			$bSpc++;
			last CHARACTER_PAIR;
		    }

		    # - Explicit breaks and non-breaks

		    # LB7(2): × (SP* ZW+)+
		    if ($lbc == LB_ZW) {
			$str->next;
			$bLen += $bSpc + 1;
			$bCM = 0;
			$bSpc = 0;

			# End of input
			last CHARACTER_PAIR if $str->eos;
			$lbc = $str->lbclass;
			next;
		    }

		    last;
		} # while (1)

		#
		# Then fill ``after'' buffer.
		#

		# - Rules for other line breaking classes

		# LB1: Assign a line breaking class to each characters.
		$str->next;

		# - Combining marks  
		# LB9: Treat X CM+ as if it were X  
		# where X is anything except BK, CR, LF, NL, SP or ZW  
		# (NB: Some CM characters may be single grapheme cluster
		# since they have Grapheme_Cluster_Break property Control.)
		while (!$str->eos && $str->lbclass == LB_CM) {
		    $str->next;
		    $aCM++;
		}
	    } # if (1)

	    # - Start of text

	    # LB2: sot ×
	    last if 0 < $bLen or 0 < $bSpc;

	    # shift buffers.
	    #XXX$bBeg += $bLen + $bSpc;
	    $bLen = $str->pos - $bBeg;
	    $bSpc = 0;
	    $bCM = $aCM;
	    $aCM = 0;
	} # CHARACTER_PAIR: while (!$str->eos)

	## Determin line breaking action by classes of adjacent characters.

	my $action;

	# Mandatory break.
	my $lbc;
	if (0 < $bSpc and
	    ($lbc = $str->lbclass($bBeg + $bLen + $bSpc - 1)) != LB_SP and
	    ($lbc != LB_CR or $eot or !$str->eos)) {
	    $action = MANDATORY;
	# LB11 - LB29 and LB31: Tailorable rules (except LB11, LB12).
        # Or urgent breaking.
	} elsif ($bBeg + $bLen + $bSpc < $str->pos) {
	    if ($str->flag($bBeg + $bLen + $bSpc) & BREAK_BEFORE) {
		$action = DIRECT;
	    } elsif ($str->flag($bBeg + $bLen + $bSpc) & PROHIBIT_BEFORE) {
		$action = PROHIBITED;
	    } elsif ($bLen == 0 and 0 < $bSpc) {
		# Prohibit break at sot or after breaking,
		# alhtough rules doesn't tell it obviously.
		$action = PROHIBITED;
	    } else {
		my ($blbc, $albc);

		$blbc = $s->lbclass_custom($str, $bBeg + $bLen - $bCM - 1);
		$albc = $s->lbclass_custom($str, $bBeg + $bLen + $bSpc);
		$action = $s->lbrule($blbc, $albc);
	    }

	    # Check prohibited break.
	    if ($action == PROHIBITED or
		($action == INDIRECT and $bSpc == 0)) {

		# When conjunction of is expected to exceed CharactersMax,
		# try urgent breaking.
		my $bsa = $str->substr($bBeg, $str->pos - $bBeg);
		if ($s->config('CharactersMax') < $bsa->chars) {
		    my $broken = $s->_urgent_break(0, '', '', $bsa);

		    #FIXME:
		        #----$broken->flag(0, BREAK_BEFORE);
			my $max = $s->config('CharactersMax');
			# If any of urgently broken fragments still
			# exceed CharactersMax, force chop them.
			if ($max and $max < $broken->chars) {
			    while ($max < $broken->chars and
				   $s->lbclass(substr($broken->as_string,
						      $max)) == LB_CM) {
				$max++;
			    }
			    my $substr = substr("$broken", 0, $max); #FIXME:
			    my $brk = Unicode::GCString->new($substr, $s);
			    $broken->flag($brk->length, BREAK_BEFORE);
			}

		    $urgEnd = $broken->length;
		    $str->substr(0, $str->pos, $broken);
		    $str->pos(0);
		    $bBeg = $bLen = $bCM = $bSpc = $aCM = 0;
		    next;
		} 
		# Otherwise, fragments may be conjuncted safely.  Read more.
		$bLen = $str->pos - $bBeg;
		$bSpc = 0;
		$bCM = $aCM;
		$aCM = 0;
		next;
	    } # if ($action == PROHIBITED or ...)
	} # if (0 < $bSpc and ...)

        # Check end of input.
        if (!$eot and $str->length <= $bBeg + $bLen + $bSpc) {
	    # Save status then output partial result.
	    $s->attr('bufstr' => $bufStr);
	    $s->attr('bufspc' => $bufSpc);
	    $s->attr('bufcols' => $bufCols);
	    $s->attr('unread' => $str->substr($bBeg));
	    $s->attr('state' => $state);
	    return $result;
        }

	# After all, possible actions are MANDATORY and other arbitrary.

	### Examine line breaking action

	my $beforeFrg = $str->substr($bBeg, $bLen);
	my $fmt;

	if ($state == 0) { # sot undone.
	    # Process start of text.
	    # FIXME:need test.
	    $fmt = $s->_format('sot', $beforeFrg);
	    if ($beforeFrg."" ne $fmt."") {
		$fmt .= $str->substr($bBeg + $bLen, $bSpc);
		$fmt .= $str->substr($bBeg + $bLen + $bSpc,
				     $str->pos - ($bBeg + $bLen + $bSpc));
		$str->substr(0, $str->pos, $fmt);
		$str->pos(0);
		$bBeg = $bLen = $bCM = $bSpc = $aCM = 0;

		$state = -1;
		next;
	    }
	    $state = 1;
	} elsif ($state == -1) {
	    $state = 1;
	} elsif ($state == 1) { # sop undone.
	    # Process start of paragraph.
	    # FIXME:need test.
	    $fmt = $s->_format('sop', $beforeFrg);
	    if ($beforeFrg."" ne $fmt."") {
		$fmt .= $str->substr($bBeg + $bLen, $bSpc);
		$fmt .= $str->substr($bBeg + $bLen + $bSpc,
				     $str->pos - ($bBeg + $bLen + $bSpc));
		$str->substr(0, $str->pos, $fmt);
		$str->pos(0);
		$bBeg = $bLen = $bCM = $bSpc = $aCM = 0;

		$state = -2;
		next;
	    }
	    $state = 2;
	} elsif ($state == -2) {
	    $state = 2;
	}

	# Check if arbitrary break is needed.
	my $newcols = $s->_sizing($bufCols, $bufStr, $bufSpc, $beforeFrg);
	if ($s->config('ColumnsMax') and $s->config('ColumnsMax') < $newcols) {
	    $newcols = $s->_sizing(0, '', '', $beforeFrg); 

	    # When arbitrary break is expected to generate very short line,
	    # or when $beforeFrg will exceed ColumnsMax, try urgent breaking.
	    if ($urgEnd < $bBeg + $bLen + $bSpc) {
		my $broken;
		if (0 < $bufCols and $bufCols < $s->config('ColumnsMin')) {
		    $broken = $s->_urgent_break($bufCols, $bufStr,
						$bufSpc, $beforeFrg);
		} elsif ($s->config('ColumnsMax') < $newcols) {
		    $broken = $s->_urgent_break(0, '', '', $beforeFrg);
		}
		if (defined $broken) {
		    $broken .= $str->substr($bBeg + $bLen, $bSpc);
		    $str->substr(0, $bBeg + $bLen + $bSpc, $broken);
		    $str->pos(0);
		    $urgEnd = $broken->length;
		    $bBeg = $bLen = $bCM = $bSpc = $aCM = 0;
		    $beforeFrg = $null; # destroy
		    next;
		}
	    }

	    # Otherwise, process arbitrary break.
	    if (length $bufStr or length $bufSpc) {
		$result .= $s->_format('', $bufStr)->as_string;
		$result .= $s->_format('eol', $bufSpc)->as_string;

		$fmt = $s->_format('sol', $beforeFrg);
		if ($beforeFrg ne $fmt) {
		    $beforeFrg = $fmt;
		    $newcols = $s->_sizing(0, '', '', $beforeFrg);
		}
	    }
	    $bufStr = $beforeFrg;
	    $bufSpc = $str->substr($bBeg + $bLen, $bSpc);
	    $bufCols = $newcols;
	# Arbitrary break is not needed.
	} else {
	    $bufStr .= $bufSpc.$beforeFrg;
	    $bufSpc = $str->substr($bBeg + $bLen, $bSpc);
	    $bufCols = $newcols;
	} # if ($s->config('ColumnsMax') and ...)

	# Mandatory break or end-of-text.
	if ($eot and $str->length <= $bBeg + $bLen + $bSpc) {
	    last;
	}
	if ($action == MANDATORY) {
	    # Process mandatory break.
	    $result .= $s->_format('', $bufStr)->as_string;
	    $result .= $s->_format('eop', $bufSpc)->as_string;
	    $state = 1; # eop done then sop must be carried out.
	    $bufStr = $null;
	    $bufSpc = $null;
	    $bufCols = 0;
	}

	# Shift buffers.
	$bBeg += $bLen + $bSpc;
	$bLen = $str->pos - $bBeg;
	$bSpc = 0;
	$bCM = $aCM;
	$aCM = 0;
    } # TEXT: while (1)

    # Process end of text.
    $result .= $s->_format('', $bufStr)->as_string;
    $result .= $s->_format('eot', $bufSpc)->as_string;

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
