#-*- perl -*-

package Unicode::LineBreak;

sub _breakable {
    my $s = shift;
    my $str = $s->{_str};
    pos($str) = $s->{_pos};

    return (EOT, '') unless $str;

#### Rules for Unicode Line Breaking Algorithm.
#### Based on Unicode Standard Annex #14 (UAX#14), Revision 22 (2008-03-31)
#### by Asmus Freytag and Andy Heninger. http://www.unicode.org/reports/tr14/

### 1 Non-tailorable Line Breaking Rules

## Resolve line breaking classes:

# LB1
    # Assign a line breaking class to each code point of the input.

## Start and end of text:

# LB2
    # sot ×

# LB3
    # ! eot
    if ($str =~ m/\G.(?=\z)/cgsx) {
	$s->{_pos} = pos($str);
	return (EOT, $&);
    }

## Mandatory breaks:

# LB4
    # BK !
    if ($str =~ m/\G$s->{lb_BK}(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (MANDATORY, $&);
    }

# LB5
    # CR × LF
    if ($str =~ m/\G$s->{lb_CR}(?=$s->{lb_LF})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # CR !
    if ($str =~ m/\G$s->{lb_CR}(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (MANDATORY, $&);
    }
    # LF !
    if ($str =~ m/\G$s->{lb_LF}(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (MANDATORY, $&);
    }
    # NL !
    if ($str =~ m/\G$s->{lb_NL}(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (MANDATORY, $&);
    }

# LB6
    # × ( BK | CR | LF | NL )
    if ($str =~ m/\G.(?=(?:$s->{lb_BK}|$s->{lb_CR}|$s->{lb_LF}|$s->{lb_NL}))/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

## Explicit breaks and non-breaks:

# LB7
    # × SP
    if ($str =~ m/\G.(?=$s->{lb_SP})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # × ZW
    if ($str =~ m/\G.(?=$s->{lb_ZW})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB8
    # ZW ÷
    if ($str =~ m/\G$s->{lb_ZW}(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (ALLOWED, $&);
    }

## Combining marks:

# LB9
    # Treat X CM* as if it were X. where X is any line break class except  BK, CR, LF, NL, SP, or ZW.

# LB10
    # Treat any remaining CM as it if were AL.

## Word joiner:

# LB11
    # × WJ
    if ($str =~ m/\G.(?=$s->{lb_WJ})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # WJ ×
    if ($str =~ m/\G$s->{lb_WJ}$s->{lb_CM}*(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

## Non-breaking characters:

# LB12
    # GL ×
    if ($str =~ m/\G$s->{lb_GL}$s->{lb_CM}*(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

### 2 Tailorable Line Breaking Rules

## Non-breaking characters:

# LB12a
    # [^SP BA HY] × GL
    if ($str =~ m/\G(?:$s->{lb_OP}$s->{lb_CM}*|$s->{lb_CL}$s->{lb_CM}*|$s->{lb_QU}$s->{lb_CM}*|$s->{lb_GL}$s->{lb_CM}*|$s->{lb_NS}$s->{lb_CM}*|$s->{lb_EX}$s->{lb_CM}*|$s->{lb_SY}$s->{lb_CM}*|$s->{lb_IS}$s->{lb_CM}*|$s->{lb_PR}$s->{lb_CM}*|$s->{lb_PO}$s->{lb_CM}*|$s->{lb_NU}$s->{lb_CM}*|(?:$s->{lb_AL}|$s->{lb_CM})$s->{lb_CM}*|$s->{lb_ID}$s->{lb_CM}*|$s->{lb_IN}$s->{lb_CM}*|$s->{lb_HY}$s->{lb_CM}*|$s->{lb_BA}$s->{lb_CM}*|$s->{lb_BB}$s->{lb_CM}*|$s->{lb_B2}$s->{lb_CM}*|$s->{lb_ZW}|$s->{lb_CM}$s->{lb_CM}*|$s->{lb_WJ}$s->{lb_CM}*|$s->{lb_H2}$s->{lb_CM}*|$s->{lb_H3}$s->{lb_CM}*|$s->{lb_JL}$s->{lb_CM}*|$s->{lb_JV}$s->{lb_CM}*|$s->{lb_JT}$s->{lb_CM}*)(?=$s->{lb_GL})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

## Opening and closing:

# LB13
    # × CL
    if ($str =~ m/\G.(?=$s->{lb_CL})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # × EX
    if ($str =~ m/\G.(?=$s->{lb_EX})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # × IS
    if ($str =~ m/\G.(?=$s->{lb_IS})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # × SY
    if ($str =~ m/\G.(?=$s->{lb_SY})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB14
    # OP SP* ×
    if ($str =~ m/\G$s->{lb_OP}$s->{lb_CM}* $s->{lb_SP}*(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB15
    # QU SP* × OP
    if ($str =~ m/\G$s->{lb_QU}$s->{lb_CM}* $s->{lb_SP}*(?=$s->{lb_OP})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB16
    # CL SP* × NS
    if ($str =~ m/\G$s->{lb_CL}$s->{lb_CM}* $s->{lb_SP}*(?=$s->{lb_NS})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB17
    # B2 SP* × B2
    if ($str =~ m/\G$s->{lb_B2}$s->{lb_CM}* $s->{lb_SP}*(?=$s->{lb_B2})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

## Spaces:

# LB18
    # SP ÷
    if ($str =~ m/\G$s->{lb_SP}(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (ALLOWED, $&);
    }

## Special case rules:

# LB19
    # × QU
    if ($str =~ m/\G.(?=$s->{lb_QU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # QU ×
    if ($str =~ m/\G$s->{lb_QU}$s->{lb_CM}*(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB20
    # ÷ CB
    if ($str =~ m/\G.(?=$s->{lb_CB})/cgsx) {
	$s->{_pos} = pos($str);
	return (ALLOWED, $&);
    }
    # CB ÷
    if ($str =~ m/\G$s->{lb_CB}$s->{lb_CM}*(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (ALLOWED, $&);
    }

# LB21
    # × BA
    if ($str =~ m/\G.(?=$s->{lb_BA})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # × HY
    if ($str =~ m/\G.(?=$s->{lb_HY})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # × NS
    if ($str =~ m/\G.(?=$s->{lb_NS})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # BB ×
    if ($str =~ m/\G$s->{lb_BB}$s->{lb_CM}*(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB22
    # AL × IN
    if ($str =~ m/\G(?:$s->{lb_AL}|$s->{lb_CM})$s->{lb_CM}*(?=$s->{lb_IN})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # ID × IN
    if ($str =~ m/\G$s->{lb_ID}$s->{lb_CM}*(?=$s->{lb_IN})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # IN × IN
    if ($str =~ m/\G$s->{lb_IN}$s->{lb_CM}*(?=$s->{lb_IN})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # NU × IN
    if ($str =~ m/\G$s->{lb_NU}$s->{lb_CM}*(?=$s->{lb_IN})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

## Numbers:

# LB23
    # ID × PO
    if ($str =~ m/\G$s->{lb_ID}$s->{lb_CM}*(?=$s->{lb_PO})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # AL × NU
    if ($str =~ m/\G(?:$s->{lb_AL}|$s->{lb_CM})$s->{lb_CM}*(?=$s->{lb_NU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # NU × AL
    if ($str =~ m/\G$s->{lb_NU}$s->{lb_CM}*(?=$s->{lb_AL})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB24
    # PR × ID
    if ($str =~ m/\G$s->{lb_PR}$s->{lb_CM}*(?=$s->{lb_ID})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # PR × AL
    if ($str =~ m/\G$s->{lb_PR}$s->{lb_CM}*(?=$s->{lb_AL})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # PO × AL
    if ($str =~ m/\G$s->{lb_PO}$s->{lb_CM}*(?=$s->{lb_AL})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB25
    # CL × PO
    if ($str =~ m/\G$s->{lb_CL}$s->{lb_CM}*(?=$s->{lb_PO})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # CL × PR
    if ($str =~ m/\G$s->{lb_CL}$s->{lb_CM}*(?=$s->{lb_PR})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # NU × PO
    if ($str =~ m/\G$s->{lb_NU}$s->{lb_CM}*(?=$s->{lb_PO})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # NU × PR
    if ($str =~ m/\G$s->{lb_NU}$s->{lb_CM}*(?=$s->{lb_PR})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # PO × OP
    if ($str =~ m/\G$s->{lb_PO}$s->{lb_CM}*(?=$s->{lb_OP})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # PO × NU
    if ($str =~ m/\G$s->{lb_PO}$s->{lb_CM}*(?=$s->{lb_NU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # PR × OP
    if ($str =~ m/\G$s->{lb_PR}$s->{lb_CM}*(?=$s->{lb_OP})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # PR × NU
    if ($str =~ m/\G$s->{lb_PR}$s->{lb_CM}*(?=$s->{lb_NU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # HY × NU
    if ($str =~ m/\G$s->{lb_HY}$s->{lb_CM}*(?=$s->{lb_NU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # IS × NU
    if ($str =~ m/\G$s->{lb_IS}$s->{lb_CM}*(?=$s->{lb_NU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # NU × NU
    if ($str =~ m/\G$s->{lb_NU}$s->{lb_CM}*(?=$s->{lb_NU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # SY × NU
    if ($str =~ m/\G$s->{lb_SY}$s->{lb_CM}*(?=$s->{lb_NU})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

## Korean syllable blocks

# LB26
    # JL × (JL | JV | H2 | H3)
    if ($str =~ m/\G$s->{lb_JL}$s->{lb_CM}*(?=(?:$s->{lb_JL}|$s->{lb_JV}|$s->{lb_H2}|$s->{lb_H3}))/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # (JV | H2) × (JV | JT)
    if ($str =~ m/\G(?:$s->{lb_JV}$s->{lb_CM}*|$s->{lb_H2}$s->{lb_CM}*)(?=(?:$s->{lb_JV}|$s->{lb_JT}))/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # (JT | H3) × JT
    if ($str =~ m/\G(?:$s->{lb_JT}$s->{lb_CM}*|$s->{lb_H3}$s->{lb_CM}*)(?=$s->{lb_JT})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB27
    # (JL | JV | JT | H2 | H3) × IN
    if ($str =~ m/\G(?:$s->{lb_JL}$s->{lb_CM}*|$s->{lb_JV}$s->{lb_CM}*|$s->{lb_JT}$s->{lb_CM}*|$s->{lb_H2}$s->{lb_CM}*|$s->{lb_H3}$s->{lb_CM}*)(?=$s->{lb_IN})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # (JL | JV | JT | H2 | H3) × PO
    if ($str =~ m/\G(?:$s->{lb_JL}$s->{lb_CM}*|$s->{lb_JV}$s->{lb_CM}*|$s->{lb_JT}$s->{lb_CM}*|$s->{lb_H2}$s->{lb_CM}*|$s->{lb_H3}$s->{lb_CM}*)(?=$s->{lb_PO})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }
    # PR × (JL | JV | JT | H2 | H3)
    if ($str =~ m/\G$s->{lb_PR}$s->{lb_CM}*(?=(?:$s->{lb_JL}|$s->{lb_JV}|$s->{lb_JT}|$s->{lb_H2}|$s->{lb_H3}))/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

## Finally, join alphabetic letters into words and break everything else. 

# LB28
    # AL × AL
    if ($str =~ m/\G(?:$s->{lb_AL}|$s->{lb_CM})$s->{lb_CM}*(?=$s->{lb_AL})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB29
    # IS × AL
    if ($str =~ m/\G$s->{lb_IS}$s->{lb_CM}*(?=$s->{lb_AL})/cgsx) {
	$s->{_pos} = pos($str);
	return (NO_BREAK, $&);
    }

# LB30 - Withdrawn

# LB31
    # ALL ÷
    if ($str =~ m/\G.(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (ALLOWED, $&);
    }
    # ÷ ALL
    if ($str =~ m/\G.(?=.)/cgsx) {
	$s->{_pos} = pos($str);
	return (ALLOWED, $&);
    }

    return NO_BREAK;
}

1;
