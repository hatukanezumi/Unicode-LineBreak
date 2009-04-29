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

B<NOTE>: This is alpha release just for proof-of-concept.

=cut

### Pragmas:
use strict;
use vars qw($VERSION @EXPORT_OK @ISA $Config);

### Exporting:
use Exporter;
our @EXPORT_OK = qw(getcontext);

### Inheritance:
our @ISA = qw(Exporter);

### Other modules:
use Carp qw(croak carp);
use Encode qw(is_utf8);
use MIME::Charset;

### Globals

### The package version, both in 1.23 style *and* usable by MakeMaker:
our $VERSION = '0.001_03';

### Public Configuration Attributes
our $Config = {
    Context => 'NONEASTASIAN',
    Format => "DEFAULT",
    HangulAsAL => 'NO',
    LegacyCM => 'YES',
    MaxColumns => 76,
    Newline => "\n",
    NSKanaAsID => 'NO',
    SizingMethod => 'DEFAULT',
};
eval { require Unicode::LineBreak::Defaults; };

### Privates
require Unicode::LineBreak::Rules;
require Unicode::LineBreak::Data;

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

# Following table describes built-in behavior by C<Format> options.
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
	return $_[0]->{Newline} if $_[1] eq 'eol';
	return $' if $_[1] =~ /^eo/ and $_[2] =~ /^$_[0]->{lb_SP}+/; #'
	undef;
    },
);

# Built-in behavior by C<SizingMethod> options.
my %SIZING_FUNCS = (
    'DEFAULT' => sub { &_strwidth(@_, 0); },
    'NARROWAL' => sub {	&_strwidth(@_, 1); },
);

sub lb_cm { &lb_CM.&lb_SAcm }
sub lb_SA { &lb_SAal.&lb_SAcm }


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

=item $self->config (KEY)

=item $self->config (KEY => VALUE, ...)

I<Instance method>.
Get or update configuration.  About KEY => VALUE pairs see L</Options>.

=back

=cut

sub config {
    my $self = shift;
    my %params = @_;
    my @opts = qw{Context Format HangulAsAL LegacyCM MaxColumns Newline
		      NSKanaAsID SizingMethod};

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

    # Other options
    foreach $o (qw{MaxColumns Newline}) {
	$self->{$o} = $Config->{$o} unless defined $self->{$o};
    }
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
    my $result = '';
    my ($l_frg, $l_spc, $l_len) = ('', '', 0);
    my ($b_frg, $b_spc, $b_cls) = ('', '', undef);
    my $sot_done = 0;
    my $sop_done = 1;
    pos($str) = 0;

    while (1) {
	my ($a_frg, $a_spc, $a_cls);

	## Chop off unbreakable fragment from text as long as possible.

	# LB3: × eot
	if ($str =~ /\G\z/cgos) {
	    $b_cls = 'eot';
	    ($a_frg, $a_spc, $a_cls) = ('', '', undef);
	# LB4, LB5, LB6: × SP* (BK | CR LF | CR | LF | NL) !
	} elsif ($str =~
		 /\G(\p{lb_SP}*
		     (?:\p{lb_BK} |
		      \p{lb_CR}\p{lb_LF} | \p{lb_CR} | \p{lb_LF} |
		      \p{lb_NL}))/cgosx) {
	    $b_spc .= $1; # $b_spc = SP* (BK etc.)
	    # LB3: × eot
	    if ($str =~ /\G\z/cgos) {
		$b_cls = 'eot';
	    } else {
		$b_cls = 'eop';
	    }
	    ($a_frg, $a_spc, $a_cls) = ('', '', undef);
	# LB7, LB8: × (ZW | SP)* ZW 
	} elsif ($str =~ /\G((?:\p{lb_ZW} | \p{lb_SP})* \p{lb_ZW})/cgox) {
	    $b_frg .= $b_spc.$1;
	    $b_spc = '';
	    $b_cls = 'ZW';
	    next;
	# LB7: × SP+
	} elsif ($str =~ /\G(\p{lb_SP}+)/cgos) {
	    $b_spc .= $1;
	    $b_cls ||= 'WJ'; # in case of --- (sot | BK etc. | ZW) × SP+
	    next;
	# LB7, LB9: Treat X CM* SP* as if it were X SP*
	# where X is anything except BK, CR, LF, NL, SP or ZW
	} elsif ($str =~ /\G(. \p{lb_cm}*) (\p{lb_SP}*)/cgosx) {
	    ($a_frg, $a_spc) = ($1, $2);

	    # LB1: Assign a line breaking class to each characters.
	    $a_cls = &_bsearch($Unicode::LineBreak::lb_MAP, $a_frg) || 'XX';
	    $a_cls = {
		'SAal' => 'AL',
		'SAcm' => 'CM',
		'SG' => 'AL',
		'XX' => 'AL',
		'AI' => ($s->{Context} eq 'EASTASIAN'? 'ID': 'AL'),
		'NSidIter' => ($s->{NSKanaAsID} =~ /ITER/? 'ID': 'NS'),
		'NSidKana' => ($s->{NSKanaAsID} =~ /SMALL/? 'ID': 'NS'),
		'NSidLong' => ($s->{NSKanaAsID} =~ /LONG/? 'ID': 'NS'),
		'NSidMasu' => ($s->{NSKanaAsID} =~ /MASU/? 'ID': 'NS'),
		'H2' => ($s->{HangulAsAL} eq 'YES'? 'AL': 'H2'),
		'H3' => ($s->{HangulAsAL} eq 'YES'? 'AL': 'H3'),
		'JL' => ($s->{HangulAsAL} eq 'YES'? 'AL': 'JL'),
		'JV' => ($s->{HangulAsAL} eq 'YES'? 'AL': 'JV'),
		'JT' => ($s->{HangulAsAL} eq 'YES'? 'AL': 'JT'),
	    }->{$a_cls} || $a_cls;

	    if ($a_cls eq 'CM') {
		# LB7, Legacy-CM: Treat SP CM+ SP* as if it were ID SP*
		# See [UAX #14] 9.1.
		if ($s->{LegacyCM} eq 'YES' and
		    defined $b_cls and $b_spc =~ s/(.)$//os) {
		    $a_frg = $1.$a_frg;
		    $a_cls = 'ID';
		    $b_cls = undef unless length $b_frg.$b_spc; # clear
		# LB7, LB10: Treat CM+ SP* as if it were AL SP*
		} else {
		    $a_cls = 'AL';
		}
	    }
	} else {
	    croak pos($str).": This should not happen: ask the developer.";
	}
	# LB2: sot ×
	unless ($b_cls) {
	    ($b_frg, $b_spc, $b_cls) =	($a_frg, $a_spc, $a_cls);
	    next;
	}

	## Determin line breaking action by classes of adjacent characters.

	my $action;
	if ($b_cls eq 'eot') {
	    $action = 'EOT';
	# LB4, LB5: (BK | CR LF | CR | LF | NL) !
	} elsif ($b_cls eq 'eop') {
	    $action = 'MANDATORY';
	# LB11 - LB29 and LB31: Tailorable rules (except LB11).
	} else {
	    my $b_idx = $Unicode::LineBreak::lb_IDX{$b_cls};
	    my $a_idx = $Unicode::LineBreak::lb_IDX{$a_cls};
	    $action = $Unicode::LineBreak::RULES_MAP->[$b_idx]->[$a_idx];
	    # LB31: ALL ÷ ALL
	    $action ||=	'DIRECT';
	    # Resolve indirect break.
	    $action = 'PROHIBITED' if $action eq 'INDIRECT' and !length $b_spc;

	    if ($action eq 'PROHIBITED') {
		$b_frg .= $b_spc.$a_frg;
		$b_spc = $a_spc;
		$b_cls = $a_cls;
		next;
	    }
	}

	## Examine line breaking action

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
	
	my $l_newlen =
	    &{$s->{_sizing_func}}($s, $l_len, $l_frg, $l_spc, $b_frg);
	if ($s->{MaxColumns} and $s->{MaxColumns} < $l_newlen) {
            # Process arbitrary break.
	    if (length $l_frg.$l_spc) {
		$result .= $s->_break('', $l_frg);
		$result .= $s->_break('eol', $l_spc);
		$b_frg = $s->_break('sol', $b_frg);
	    }
	    $l_frg = $b_frg;
	    $l_len = &{$s->{_sizing_func}}($s, 0, '', '', $b_frg);
	    $l_spc = $b_spc;
	} else {
	    $l_frg .= $l_spc.$b_frg;
	    $l_len = $l_newlen;
	    $l_spc = $b_spc;
	}
	($b_frg, $b_spc, $b_cls) = ($a_frg, $a_spc, $a_cls);

	if ($action eq 'MANDATORY') {
	    # Process mandatory break.
	    $result .= $s->_break('', $l_frg);
	    $result .= $s->_break('eop', $l_spc);
	    $sop_done = 0;
	    $l_frg = '';
	    $l_len = 0;
	    $l_spc = '';
	} elsif ($action eq 'EOT') {
	    # Process end of text.
	    $result .= $s->_break('', $l_frg);
	    $result .= $s->_break('eot', $l_spc);
	    last;
	}
    }

    ## Return result.
    $result;
}

=over 4

=item getcontext([Charset => CHARSET], [Language => LANGUAGE])

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
	    $charset = MIME::Charset->new($opts{$k})->as_string;
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

=head2 Options

L<new> and L<config> methods accept following pairs.

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

Insert or replace newline sequences by that specified by Newline option,
remove SPACEs leading newline sequences or end-of-text.  Then append newline
at end of text if it does not exist.

=item C<"TRIM">

Insert newline at arbitrary breaking positions. Remove SPACEs leading
newline sequences.

=item Subroutine reference

See L</"Customizing Line Breaking Behavior">.

=back

See also Newline option.

=item HangulAsAL => C<"YES"> | C<"NO">

Treat hangul syllables and conjoining jamos as alphabetic characters (AL).
Default is C<"NO">.

=item LegacyCM => C<"YES"> | C<"NO">

Treat combining characters lead by SPACE as an isolated combining character.
As of Unicode 5.0, such use of SPACE is not recommended.
Default is C<"YES">.

=item MaxColumns => NUMBER

Maximum number of columns line may include not counting trailing spaces and
newline sequence.  In other words, maximum length of line.
Default is C<76>.

=item Newline => STRING

Unicode string to be used for newline sequence.
Default is C<"\n">.

=item NSKanaAsID => C<">CLASS...C<">

Treat some non-starters (NS) as normal ideographic characters (ID)
based on classification specified by CLASS.
CLASS may include following substrings.

=over 4

=item C<"ALL">

All of characters below.
Synonym is C<"YES">.

=item C<"ITERATION MARKS">

Ideographic iteration marks.

N.B. Some of them are neither hiragana nor katakana.

=item C<"KANA SMALL LETTERS">, C<"PROLONGED SOUND MARKS">

Hiragana or katakana small letters and prolonged sound marks.

N.B. These letters are optionally treated either as non-starter or
as normal ideographic.  See [JIS X 4051] 6.1.1.

=item C<"MASU MARK">

U+303C MASU MARK.

N.B. Although this character is not kana, it is usually regarded as
abbreviation to sequence of hiragana C<"ます"> or katakana C<"マス">,
MA and SU.

N.B. This character is classified as Non-starter (NS) by [UAX #14]
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
By this option those characters are treated as narrow.

=item Subroutine reference

See L</"Customizing Line Breaking Behavior">.

=back

=back

=head2 Customizing Line Breaking Behavior

=head3 Formatting Lines

If you specify subroutine reference as a value of C<Format> option,
it should accept three arguments: Instance of LineBreak object, type of
event and a string.
Type of event is string to determine the context that subroutine is
called in.
String is a fragment of Unicode string leading or trailing breaking position.

    EVENT |When Fired           |Value of STRING
    -----------------------------------------------------------------
    "sot" |Beginning of text    |Fragment of first line
    "sop" |After mandatory break|Fragment of next line
    "sol" |After arbitrary break|Fragment on sequel of line
    ""    |Just before any break|Complete line without trailing
          |                     |SPACEs
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

=head3 Calculating String Size

If you specify subroutine reference as a value of C<SizingMethod> option,
it should accept five arguments: Instance of LineBreak object,
original size of string (say LEN), origianl Unicode string (PRE),
additional SPACEs (SPC) and Unicode string (STR).

Subroutine should return calculated size of C<PRE.SPC.STR>.

=cut

# self->_strwidth(LEN, PRE, SPC, STR, NARROWAL)
sub _strwidth {
    my $self = shift;
    my $len = shift;
    my $pre = shift;
    my $spc = shift;
    my $str = shift;
    my $narrowal;
    return $len unless defined $str and length $str;

    my $result = $len;

    my $width;
    my $spcstr = $spc.$str;
    pos($spcstr) = 0;
    while (1) {
	if ($spcstr =~ /\G\z/cgos) {
	    last;
	# LB26: Korean syllable blocks
	#   (JL* H3 JT* | JL* H2 JV* JT* | JL* JV+ JT* | JL+ | JT+)
	# N.B. [UAX #14] allows some morbid "syllable blocks" such as
	#   JL CM JV JT
	# which might be broken into JL CM and rest.
	} elsif ($spcstr =~ /
		 \G
		 (?:\p{lb_JL}* \p{lb_H3} \p{lb_JT}* |
		  \p{lb_JL}* \p{lb_H2} \p{lb_JV}* \p{lb_JT}* |
		  \p{lb_JL}* \p{lb_JV}+ \p{lb_JT}* |
		  \p{lb_JL}+ | \p{lb_JT}+
		  )
		 /cgox) {
	    $width = 'W';
	} else {
	    $spcstr =~ /\G(.)/gos;
	    $width = &_bsearch($Unicode::LineBreak::ea_MAP, $1);
	    $width = {
		'AnLat' => ($narrowal? 'Na': 'A'),
		'AnGre' => ($narrowal? 'Na': 'A'),
		'AnCyr' => ($narrowal? 'Na': 'A'),
	    }->{$width} || $width;
	}
	if ($width eq 'F' or $width eq 'W') {
	    $result += 2;
        } elsif ($self->{Context} eq 'EASTASIAN' and $width eq 'A') {
            $result += 2;
	} elsif ($width ne 'z') {
	    $result += 1;
	}
    }
    return $result;
}

=head3 Character Classifications and Core Line Breaking Rules

Classifications of character and core line breaking rules are defined by
L<Unicode::LineBreak::Data> and L<Unicode::LineBreak::Rules>.
If you wish to customize them, see F<data> directory of source package.

=cut

## Helper functions.

# _bearch MAP, VAL
# Examine binary search on property map table with following structure:
# [
#     [start, stop, property_value],
#     ...
# ]
# where start and stop stands for a continuous range of UCS ordinal those
# are assigned property_value.
sub _bsearch {
    my $map = shift;
    my $val = ord shift;

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


=head2 Configuration Files

Built-in defaults of option parameters for L<"new"> method
can be overridden by configuration files:
F<Unicode/LineBreak/Defaults.pm>.
For more details read F<Unicode/LineBreak/Defaults.pm.sample>.

=head2 Conformance to Standards

Character properties based on by this module are defined by
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

=head1 CAVEAT

I<To be written>.

=head1 BUGS

Please report bugs or buggy behaviors to developer.  See L</AUTHOR>.

=head1 VERSION

Consult $VERSION variable.

Development versions of this module may be found at 
L<http://hatuka.nezumi.nu/repos/Unicode-LineBreak/>.

=head1 REFERENCES

=over 4

=item [JIS X 4051]

JIS X 4051:2004
I<日本語文書の組版方法> (I<Formatting Rules for Japanese Documents>),
published by Japanese Standards Association, 2004.

=begin comment

=item [JLREQ]

Y. Anan, H. Chiba, J. Edamoto et al (2008).
I<Requirements of Japanese Text Layout: W3C Working Draft 15 October 2008>.
L<http://www.w3.org/TR/2008/WD-jlreq-20081015/>.

=end comment

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

L<Text::Wrap>.

=head1 AUTHOR

Copyright (C) 2009 Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>.

This program is free software; you can redistribute it and/or modify it 
under the same terms as Perl itself.

=cut

1;
