#-*- perl -*-

package Unicode::LineBreak;
require 5.008;

=encoding utf8

=head1 NAME

Unicode::LineBreak - UAX #14 Unicode Line Breaking Algorithm

=head1 SYNOPSIS

    use Unicode::LineBreak;
    $lb = Unicode::LineBreak->new($string);
    $string = $lb->break;

=head1 DESCRIPTION

Unicode::LineBreak performs Line Breaking Algorithm described in
Unicode Standards Annex #14 [UAX #14].  East_Asian_Width informative
properties [UAX #11] will be concerned to determin breaking positions.

B<NOTE>: Current release of this module is pre-alpha just for proof-of-concept.

=cut

### Pragmas:
use strict;
use vars qw($VERSION @EXPORT_OK @ISA $Config);

### Exporting:
use Exporter;

### Inheritance:
@ISA = qw(Exporter);

### Other modules:
use Carp qw(croak carp);
use Encode;
use MIME::Charset qw(:info);

### Globals

### The package version, both in 1.23 style *and* usable by MakeMaker:
$VERSION = '0.001_03';

### Public Configuration Attributes
our $Config = {
    %{$MIME::Charset::Config}, # Detect7bit, Replacement, Mapping
    Break => "\n",
    Charset => 'UTF-8',
    Context => '',
    HangulAsAL => 'NO',
    Language => 'XX',
    LegacyCM => 'YES',
    MaxColumns => 76,
    NSKanaAsID => 'NO',
    OutputCharset => 'UTF-8',
};
eval { require Unicode::LineBreak::Defaults; };

### Privates
require Unicode::LineBreak::Rules;
require Unicode::LineBreak::Data;

my @ALL_CLASSES = qw(BK CR LF CM NL SG WJ ZW GL SP B2 BA BB HY CB CL EX IN NS OP QU IS NU PO PR SY AI AL H2 H3 ID JL JV JT SA XX);  

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


=head2 Public Interface

=over 4

=item new STRING, [OPTIONS, ...]

Constructor.  Following OPTIONS may be specified.

=over 4

=item Breaking => METHOD

I<Not yet implemented>.
Specify the method to format broken lines.

=over 4

=item C<"DEFAULT">

Default method.  Insert newline at arbitrary breaking positions.

=item C<"NEWLINE">

Remove SPACEs leading newline sequences, and append newline at end of text
if it does not exist.

=item C<"TRIM">

Remove SPACEs leading newline sequences.

=item Subroutine reference

See L</"Costomizing Line Breaking Behavior">.

=back

See also Newline option.

=item Charset => CHARSET

Character set that is used to encode string STRING.
Default is C<"UTF-8">.

=item Context => CONTEXT

Along with Charset option, this may be used to define language/region
context.
Currently available contexts are C<"EASTASIAN"> and C<"NONEASTASIAN">.
Default context is C<"NONEASTASIAN">.

=item HangulAsAL => C<"YES"> | C<"NO">

Treat hangul syllables and conjoining jamos as alphabetic characters (AL).
Default is C<"NO">.

=item Language => LANGUAGE

Along with Charset option, this may be used to define language/region
context.
See Context option.

=item LegacyCM => C<"YES"> | C<"NO">

Treat combining characters lead by SPACE as an isolated combining character.
As of Unicode 5.0, such use of SPACE is not recommended.
Default is C<"YES">.

=item MaxColumns => NUMBER

Maximum number of columns line may include not counting trailing spaces and
newline sequence.  In other words, maximum length of line.
Default is C<76>.

=item Newline => STRING

I<Not yet implemented>.
Replace newline sequences with Unicode string STRING.
If C<undef> is specified, newline sequences will not be modified.
Default is C<undef>.

=item NSKanaAsID => C<"YES"> | C<"NO">

Treat hiragana/katakana small letters and prolonged signs (NS) as
ideographic characters (ID).
This feature is optional in [JIS X 4051].
Default is C<"NO">.

=item OutputCharset => CHARSET

Character set that is used to encode result of break().
If a special value C<"_UNICODE_"> is specified, result will be Unicode string.
Default is C<"UTF-8">.

=back

=back

=cut

sub new {
    my $class = shift;
    my $str = shift;

    my $self = { };
    &config($self, @_);
    if (Encode::is_utf8($str)) {
	$self->{_str} = $str;
    } else {
	$self->{_str} = $self->{_charset}->decode($str);
    }
    bless $self, $class;
}

sub config {
    my $self = shift;
    my %params = @_;

    ## Get Options.

    # Character set and language assumed.
    my $charset = uc($params{Charset} || $Config->{Charset});
    $self->{_charset} = MIME::Charset->new($charset);
    my $ocharset = uc($params{OutputCharset} || $charset);
    $self->{_output_charset} = $ocharset;
    if ($ocharset ne '_UNICODE_') {
	$self->{_charset}->encoder(MIME::Charset->new($ocharset));
    }
    $self->{_language} = uc($params{Language} || $Config->{Language});
    $self->{_language} =~ s/_/-/g;
    $self->{_legacy_cm} = uc($params{LegacyCM} || $Config->{LegacyCM});
    $self->{_max_columns} = $params{MaxColumns} || $Config->{MaxColumns};

    # Context. Either East Asian or Non-East Asian.
    my $context = uc($params{Context} || $Config->{Context});
    if ($context =~ /^(N(ON)?)?EA(STASIAN)?/) {
	if ($context =~ /^N/) {
	    $context = 'NONEASTASIAN';
	} else {
	    $context = 'EASTASIAN';
	}
    } elsif ($self->{_charset}->as_string =~ /$EASTASIAN_CHARSETS/) {
        $context = 'EASTASIAN';
    } elsif ($self->{_language} =~ /$EASTASIAN_LANGUAGES/) {
	$context = 'EASTASIAN';
    } else {
	$context = 'NONEASTASIAN';
    }
    $self->{_context} = $context;

    # Some flags
    $self->{_ns_kana_as_id} = uc($params{NSKanaAsID} || $Config->{NSKanaAsID});
    $self->{_hangul_as_al} = uc($params{HangulAsAL} || $Config->{HangulAsAL});
    $self->{_newline} = "\n";

    ## Customize Line Breaking Classes.

    my %lb;
    foreach my $c (qw{BK CR LF NL SP ZW CM H2 H3 JL JV JT}) {
	$lb{$c} = [$c];
    }
    push @{$lb{CM}}, 'SAcm'; # Resolve SA: See UAX #14 6.1 LB1.
    $lb{SA} = [qw{SAcm SAal}];
    $lb{hangul} = [qw{H3 H2 JL JV JT}];
    foreach my $c (keys %lb) {
	$self->{"lb_$c"} = '(?:' .
	    (join '|', map qr{\p{lb_$_}}, @{$lb{$c}}) .
	    ')';
    }
}

=over 4

=item break

Instance method.  Break string and returns it.

=back

=cut

sub break {
    my $s = shift;
    my $str = $s->{_str};
    return '' unless defined $str and length $str;

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
	if ($str =~ /\G\z/cgs) {
	    $b_cls = 'eot';
	    ($a_frg, $a_spc, $a_cls) = ('', '', undef);
	# LB5, LB6: × SP* (BK | CR LF | CR | LF | NL) !
	} elsif ($str =~
		 /\G(?:$s->{lb_BK}|
		     $s->{lb_CR}$s->{lb_LF}|
		     $s->{lb_CR}|
		     $s->{lb_LF}|
		     $s->{lb_NL})/cgsx) {
	    $b_spc .= $&; #XXX $b_spc = SP* (BK etc.)
	    $b_cls = 'eop';
	    # LB3, LB5, LB6: × SP* (BK etc.) eot
	    if ($str =~ /\G\z/cgs) {
		$b_cls = 'eot';
	    }
	    ($a_frg, $a_spc, $a_cls) = ('', '', undef);
	# LB7, LB8: × (ZW | SP)* ZW 
	} elsif ($str =~ /\G(?:$s->{lb_ZW}|$s->{lb_SP})*$s->{lb_ZW}/cgs) {
	    $b_frg .= $b_spc.$&;
	    $b_spc = '';
	    $b_cls = 'ZW';
	    next;
	# LB7: × SP+
	} elsif ($str =~ /\G$s->{lb_SP}+/cgs) {
	    $b_spc .= $&;
	    $b_cls ||= 'WJ'; # in case of --- (sot | BK etc. | ZW) × SP+
	    next;
	# LB7, LB9, LB26, LB27: Treat
	#   (JL* H3 JT* | JL* H2 JV* JT* | JL* JV+ JT* | JL+ | JT+) CM* SP*
	# as if it were ID CM* SP* (or optionally AL CM* SP*)
	} elsif ($str =~
		 /\G((?:
		      $s->{lb_JL}* $s->{lb_H3} $s->{lb_JT}* |
		      $s->{lb_JL}* $s->{lb_H2} $s->{lb_JV}* $s->{lb_JT}* |
		      $s->{lb_JL}* $s->{lb_JV}+ $s->{lb_JT}* |
		      $s->{lb_JL}+ | $s->{lb_JT}+)
		     $s->{lb_CM}*) ($s->{lb_SP}*)/cgsx) {
	    ($a_frg, $a_spc) = ($1, $2);
	    if ($s->{_hangul_as_al} eq 'YES') {
		$a_cls = 'AL';
	    } else {
		$a_cls = 'ID';
	    }
	# LB7, LB9: Treat X CM* SP* as if it were X SP*
	# where X is anything except BK, CR, LF, NL, SP or ZW
	} elsif ($str =~ /\G(.$s->{lb_CM}*)($s->{lb_SP}*)/cgs) {
	    ($a_frg, $a_spc) = ($1, $2);

	    # LB1: Assign a line breaking class to each characters.
	    $a_cls = &_bsearch($Unicode::LineBreak::lb_MAP, $a_frg) || 'XX';
	    $a_cls = {
		'SAcm' => 'CM',
		'SAal' => 'AL',
		'SG' => 'AL',
		'XX' => 'AL',
		'AI' => ($s->{_context} eq 'EASTASIAN'? 'ID': 'AL'),
		'NSid' => ($s->{_ns_kana_as_id} eq 'YES'? 'ID': 'NS'),
	    }->{$a_cls} || $a_cls;

	    if ($a_cls eq 'CM') {
		# LB7, Legacy-CM: Treat SP CM+ SP* as if it were ID SP*
		# See [UAX #14] 9.1.
		if ($s->{_legacy_cm} and
		    defined $b_cls and $b_spc =~ s/.$//os) {
		    $a_frg = $&.$a_frg;
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
	
	my $l_newlen = $s->_strwidth($l_len, $l_frg, $l_spc, $b_frg);
	if ($s->{_max_columns} < $l_newlen) {
            # Process arbitrary break.
	    if (length $l_frg.$l_spc) {
		$result .= $l_frg.$s->_break('eol', $l_spc);
		$b_frg = $s->_break('sol', $b_frg);
	    }
	    $l_frg = $b_frg;
	    $l_len = $s->_strwidth(0, '', '', $b_frg);
	    $l_spc = $b_spc;
	} else {
	    $l_frg .= $l_spc.$b_frg;
	    $l_len = $l_newlen;
	    $l_spc = $b_spc;
	}
	($b_frg, $b_spc, $b_cls) = ($a_frg, $a_spc, $a_cls);

	if ($action eq 'MANDATORY') {
	    # Process mandatory break.
	    $result .= $l_frg.$s->_break('eop', $l_spc);
	    $sop_done = 0;
	    $l_frg = '';
	    $l_len = 0;
	    $l_spc = '';
	} elsif ($action eq 'EOT') {
	    # Process end of text.
	    $result .= $l_frg.$s->_break('eot', $l_spc);
	    last;
	}
    }

    ## Output

    if ($s->{_output_charset} eq '_UNICODE_') {
	return $result;
    } else {
	return $s->{_charset}->encode($result);
    }
}

=head2 Customizing Line Breaking Behavior

If you specify subroutine reference as a value of Breaking option,
it should accept three arguments: Instance of LineBreak object, ACTION and
STRING.
ACTION is a string to determine the context that subroutine is called in.
STRING is a fragment of text leading or trailing breaking position.

    ACTION| When Fired            | Value of STRING
    ------+-----------------------+---------------------------------
    "sot" | Beginning of text     | Fragment of first line
    "sop" | After mandatory break | Fragment of next line
    "sol" | After arbitrary break | Fragment at sequel of line
    "eol" | Arabitrary break      | Leading SPACEs at breaking position
    "eop" | Mandatory break       | Leading SPACEs and newline
    "eot" | End of text           | Leading SPACEs (and newline)
    ----------------------------------------------------------------

Subroutine should return modified text fragment or may return
C<undef> to express that no modification occurred.
Note that modification in the context of C<"sot">, C<"sop"> or C<"sol"> may
affect decision of successive breaking positions while in the others won't.

Following table describes built-in behavior by Breaking options.

          | "DEFAULT"       | "TRIM"            | "NEWLINE"
    ------+-----------------+-------------------+-------------------
    "sot" | do nothing      | do nothing        | do nothing
    "sop" | do nothing      | do nothing        | do nothing
    "sol" | do nothing      | do nothing        | do nothing
    "eol" | append newline  | replace by newline| replace by newline
    "eop" | do nothing      | replace by newline| replace by newline
    "eot" | do nothing      | remove SPACEs     | replace by newline
    ----------------------------------------------------------------

=cut

my $break_func_default = sub {
    my $self = shift;
    my $action = shift;
    my $str = shift;

    if ($action eq 'sot' or      # Start of text.
	$action eq 'sop' or      # New line after Mandatory break.
	$action eq 'sol') {      # New line after Arbtrary break.
	return $str;
    } elsif ($action eq 'eol') { # Arabitrary break.
	return $str.$self->{_newline};
    } elsif ($action eq 'eop') { # Mandatory break.
	return $str;
    } elsif ($action eq 'eot') { # End of text.
	return $str;
    } else {
	croak "Unknown line breaking action: $action";
    }
};

sub _break {
    my $self = shift;
    my $action = shift || '';
    my $spc = shift;

    my $func = $self->{_break_func} || $break_func_default;
    my $result;
    my $err = $@;
    eval {
	$result = &{$func}($self, $action, $spc);
    };
    if ($@) {
	carp $@;
	$result = $spc;
    } elsif (!defined $result) {
	$result = $spc;
    }
    $@ = $err;
    return $result;
}


# Helper functions.

# self->_strwidth(LEN, PRE, SPC, STR)
# Increment number of columns by that newly added string will occupy.
# LEN is the columns of string PRE.
# SPC is a sequence of SPACE inserted between PRE and STR.
# Returns recalculated number of columns of PRE.SPC.STR.
# TODO: Adjust widths of hangul conjoining jamos.
sub _strwidth {
    my $self = shift;
    my $len = shift;
    my $pre = shift;
    my $spc = shift;
    my $str = shift;
    my $result = $len;

    return $len unless defined $str and length $str;
    my $i;
    for ($i = 0; $i < length($spc.$str); $i++) {
	my $width = &_bsearch($Unicode::LineBreak::ea_MAP,
			      substr($spc.$str, $i, 1));
	if ($width eq 'F' or $width eq 'W') {
	    $result += 2;
        } elsif ($self->{_context} eq 'EASTASIAN' and $width eq 'A') {
            $result += 2;
	} elsif ($width ne 'z') {
	    $result += 1;
	}
    }
    return $result;
}

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
F<MIME/Charset/Defaults.pm> and F<Unicode/LineBreak/Defaults.pm>.
For more details read F<Unicode/LineBreak/Defaults.pm.sample>.

=head2 Conformance to Standards

Character properties based on by this module are defined by
Unicode Standards version 5.1.0.

This module is intended to implement UAX14-C2.

=over 4

=item *

Hiragana/katakana small letters and prolonged signs may be treated as
either NS or ID by choice (See [JIS X 4051] 6.1.1).

=item *

Hangul syllables and conjoining jamos may be treated as
either H2/H3/JL/JT/JV or AL by choice.

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
