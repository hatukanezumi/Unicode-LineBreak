#-*- perl -*-

package Unicode::LineBreak;

sub setRules {
    my $self = shift;
    my @rules = ();

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
    push @rules, [qr{\G.(?=\z)}osx, EOT];

## Mandatory breaks:

# LB4
    # BK !
    push @rules, [qr{\G$self->{lb_BK}(?=.)}osx, MANDATORY];

# LB5
    # CR × LF
    push @rules, [qr{\G$self->{lb_CR}(?=$self->{lb_LF})}osx, NO_BREAK];
    # CR !
    push @rules, [qr{\G$self->{lb_CR}(?=.)}osx, MANDATORY];
    # LF !
    push @rules, [qr{\G$self->{lb_LF}(?=.)}osx, MANDATORY];
    # NL !
    push @rules, [qr{\G$self->{lb_NL}(?=.)}osx, MANDATORY];

# LB6
    # × ( BK | CR | LF | NL )
    push @rules, [qr{\G.(?=(?:$self->{lb_BK}|$self->{lb_CR}|$self->{lb_LF}|$self->{lb_NL}))}osx, NO_BREAK];

## Explicit breaks and non-breaks:

# LB7
    # × SP
    push @rules, [qr{\G.(?=$self->{lb_SP})}osx, NO_BREAK];
    # × ZW
    push @rules, [qr{\G.(?=$self->{lb_ZW})}osx, NO_BREAK];

# LB8
    # ZW ÷
    push @rules, [qr{\G$self->{lb_ZW}(?=.)}osx, ALLOWED];

## Combining marks:

# LB9
    # Treat X CM* as if it were X. where X is any line break class except  BK, CR, LF, NL, SP, or ZW.

# LB10
    # Treat any remaining CM as it if were AL.

## Word joiner:

# LB11
    # × WJ
    push @rules, [qr{\G.(?=$self->{lb_WJ})}osx, NO_BREAK];
    # WJ ×
    push @rules, [qr{\G$self->{lb_WJ}$self->{lb_CM}*(?=.)}osx, NO_BREAK];

## Non-breaking characters:

# LB12
    # GL ×
    push @rules, [qr{\G$self->{lb_GL}$self->{lb_CM}*(?=.)}osx, NO_BREAK];

### 2 Tailorable Line Breaking Rules

## Non-breaking characters:

# LB12a
    # [^SP BA HY] × GL
    push @rules, [qr{\G(?:$self->{lb_OP}$self->{lb_CM}*|$self->{lb_CL}$self->{lb_CM}*|$self->{lb_QU}$self->{lb_CM}*|$self->{lb_GL}$self->{lb_CM}*|$self->{lb_NS}$self->{lb_CM}*|$self->{lb_EX}$self->{lb_CM}*|$self->{lb_SY}$self->{lb_CM}*|$self->{lb_IS}$self->{lb_CM}*|$self->{lb_PR}$self->{lb_CM}*|$self->{lb_PO}$self->{lb_CM}*|$self->{lb_NU}$self->{lb_CM}*|(?:$self->{lb_AL}|$self->{lb_CM})$self->{lb_CM}*|$self->{lb_ID}$self->{lb_CM}*|$self->{lb_IN}$self->{lb_CM}*|$self->{lb_HY}$self->{lb_CM}*|$self->{lb_BA}$self->{lb_CM}*|$self->{lb_BB}$self->{lb_CM}*|$self->{lb_B2}$self->{lb_CM}*|$self->{lb_ZW}|$self->{lb_CM}$self->{lb_CM}*|$self->{lb_WJ}$self->{lb_CM}*|$self->{lb_H2}$self->{lb_CM}*|$self->{lb_H3}$self->{lb_CM}*|$self->{lb_JL}$self->{lb_CM}*|$self->{lb_JV}$self->{lb_CM}*|$self->{lb_JT}$self->{lb_CM}*)(?=$self->{lb_GL})}osx, NO_BREAK];

## Opening and closing:

# LB13
    # × CL
    push @rules, [qr{\G.(?=$self->{lb_CL})}osx, NO_BREAK];
    # × EX
    push @rules, [qr{\G.(?=$self->{lb_EX})}osx, NO_BREAK];
    # × IS
    push @rules, [qr{\G.(?=$self->{lb_IS})}osx, NO_BREAK];
    # × SY
    push @rules, [qr{\G.(?=$self->{lb_SY})}osx, NO_BREAK];

# LB14
    # OP SP* ×
    push @rules, [qr{\G$self->{lb_OP}$self->{lb_CM}* $self->{lb_SP}*(?=.)}osx, NO_BREAK];

# LB15
    # QU SP* × OP
    push @rules, [qr{\G$self->{lb_QU}$self->{lb_CM}* $self->{lb_SP}*(?=$self->{lb_OP})}osx, NO_BREAK];

# LB16
    # CL SP* × NS
    push @rules, [qr{\G$self->{lb_CL}$self->{lb_CM}* $self->{lb_SP}*(?=$self->{lb_NS})}osx, NO_BREAK];

# LB17
    # B2 SP* × B2
    push @rules, [qr{\G$self->{lb_B2}$self->{lb_CM}* $self->{lb_SP}*(?=$self->{lb_B2})}osx, NO_BREAK];

## Spaces:

# LB18
    # SP ÷
    push @rules, [qr{\G$self->{lb_SP}(?=.)}osx, ALLOWED];

## Special case rules:

# LB19
    # × QU
    push @rules, [qr{\G.(?=$self->{lb_QU})}osx, NO_BREAK];
    # QU ×
    push @rules, [qr{\G$self->{lb_QU}$self->{lb_CM}*(?=.)}osx, NO_BREAK];

# LB20
    # ÷ CB
    push @rules, [qr{\G.(?=$self->{lb_CB})}osx, ALLOWED];
    # CB ÷
    push @rules, [qr{\G$self->{lb_CB}$self->{lb_CM}*(?=.)}osx, ALLOWED];

# LB21
    # × BA
    push @rules, [qr{\G.(?=$self->{lb_BA})}osx, NO_BREAK];
    # × HY
    push @rules, [qr{\G.(?=$self->{lb_HY})}osx, NO_BREAK];
    # × NS
    push @rules, [qr{\G.(?=$self->{lb_NS})}osx, NO_BREAK];
    # BB ×
    push @rules, [qr{\G$self->{lb_BB}$self->{lb_CM}*(?=.)}osx, NO_BREAK];

# LB22
    # AL × IN
    push @rules, [qr{\G(?:$self->{lb_AL}|$self->{lb_CM})$self->{lb_CM}*(?=$self->{lb_IN})}osx, NO_BREAK];
    # ID × IN
    push @rules, [qr{\G$self->{lb_ID}$self->{lb_CM}*(?=$self->{lb_IN})}osx, NO_BREAK];
    # IN × IN
    push @rules, [qr{\G$self->{lb_IN}$self->{lb_CM}*(?=$self->{lb_IN})}osx, NO_BREAK];
    # NU × IN
    push @rules, [qr{\G$self->{lb_NU}$self->{lb_CM}*(?=$self->{lb_IN})}osx, NO_BREAK];

## Numbers:

# LB23
    # ID × PO
    push @rules, [qr{\G$self->{lb_ID}$self->{lb_CM}*(?=$self->{lb_PO})}osx, NO_BREAK];
    # AL × NU
    push @rules, [qr{\G(?:$self->{lb_AL}|$self->{lb_CM})$self->{lb_CM}*(?=$self->{lb_NU})}osx, NO_BREAK];
    # NU × AL
    push @rules, [qr{\G$self->{lb_NU}$self->{lb_CM}*(?=$self->{lb_AL})}osx, NO_BREAK];

# LB24
    # PR × ID
    push @rules, [qr{\G$self->{lb_PR}$self->{lb_CM}*(?=$self->{lb_ID})}osx, NO_BREAK];
    # PR × AL
    push @rules, [qr{\G$self->{lb_PR}$self->{lb_CM}*(?=$self->{lb_AL})}osx, NO_BREAK];
    # PO × AL
    push @rules, [qr{\G$self->{lb_PO}$self->{lb_CM}*(?=$self->{lb_AL})}osx, NO_BREAK];

# LB25
    # CL × PO
    push @rules, [qr{\G$self->{lb_CL}$self->{lb_CM}*(?=$self->{lb_PO})}osx, NO_BREAK];
    # CL × PR
    push @rules, [qr{\G$self->{lb_CL}$self->{lb_CM}*(?=$self->{lb_PR})}osx, NO_BREAK];
    # NU × PO
    push @rules, [qr{\G$self->{lb_NU}$self->{lb_CM}*(?=$self->{lb_PO})}osx, NO_BREAK];
    # NU × PR
    push @rules, [qr{\G$self->{lb_NU}$self->{lb_CM}*(?=$self->{lb_PR})}osx, NO_BREAK];
    # PO × OP
    push @rules, [qr{\G$self->{lb_PO}$self->{lb_CM}*(?=$self->{lb_OP})}osx, NO_BREAK];
    # PO × NU
    push @rules, [qr{\G$self->{lb_PO}$self->{lb_CM}*(?=$self->{lb_NU})}osx, NO_BREAK];
    # PR × OP
    push @rules, [qr{\G$self->{lb_PR}$self->{lb_CM}*(?=$self->{lb_OP})}osx, NO_BREAK];
    # PR × NU
    push @rules, [qr{\G$self->{lb_PR}$self->{lb_CM}*(?=$self->{lb_NU})}osx, NO_BREAK];
    # HY × NU
    push @rules, [qr{\G$self->{lb_HY}$self->{lb_CM}*(?=$self->{lb_NU})}osx, NO_BREAK];
    # IS × NU
    push @rules, [qr{\G$self->{lb_IS}$self->{lb_CM}*(?=$self->{lb_NU})}osx, NO_BREAK];
    # NU × NU
    push @rules, [qr{\G$self->{lb_NU}$self->{lb_CM}*(?=$self->{lb_NU})}osx, NO_BREAK];
    # SY × NU
    push @rules, [qr{\G$self->{lb_SY}$self->{lb_CM}*(?=$self->{lb_NU})}osx, NO_BREAK];

## Korean syllable blocks

# LB26
    # JL × (JL | JV | H2 | H3)
    push @rules, [qr{\G$self->{lb_JL}$self->{lb_CM}*(?=(?:$self->{lb_JL}|$self->{lb_JV}|$self->{lb_H2}|$self->{lb_H3}))}osx, NO_BREAK];
    # (JV | H2) × (JV | JT)
    push @rules, [qr{\G(?:$self->{lb_JV}$self->{lb_CM}*|$self->{lb_H2}$self->{lb_CM}*)(?=(?:$self->{lb_JV}|$self->{lb_JT}))}osx, NO_BREAK];
    # (JT | H3) × JT
    push @rules, [qr{\G(?:$self->{lb_JT}$self->{lb_CM}*|$self->{lb_H3}$self->{lb_CM}*)(?=$self->{lb_JT})}osx, NO_BREAK];

# LB27
    # (JL | JV | JT | H2 | H3) × IN
    push @rules, [qr{\G(?:$self->{lb_JL}$self->{lb_CM}*|$self->{lb_JV}$self->{lb_CM}*|$self->{lb_JT}$self->{lb_CM}*|$self->{lb_H2}$self->{lb_CM}*|$self->{lb_H3}$self->{lb_CM}*)(?=$self->{lb_IN})}osx, NO_BREAK];
    # (JL | JV | JT | H2 | H3) × PO
    push @rules, [qr{\G(?:$self->{lb_JL}$self->{lb_CM}*|$self->{lb_JV}$self->{lb_CM}*|$self->{lb_JT}$self->{lb_CM}*|$self->{lb_H2}$self->{lb_CM}*|$self->{lb_H3}$self->{lb_CM}*)(?=$self->{lb_PO})}osx, NO_BREAK];
    # PR × (JL | JV | JT | H2 | H3)
    push @rules, [qr{\G$self->{lb_PR}$self->{lb_CM}*(?=(?:$self->{lb_JL}|$self->{lb_JV}|$self->{lb_JT}|$self->{lb_H2}|$self->{lb_H3}))}osx, NO_BREAK];

## Finally, join alphabetic letters into words and break everything else. 

# LB28
    # AL × AL
    push @rules, [qr{\G(?:$self->{lb_AL}|$self->{lb_CM})$self->{lb_CM}*(?=$self->{lb_AL})}osx, NO_BREAK];

# LB29
    # IS × AL
    push @rules, [qr{\G$self->{lb_IS}$self->{lb_CM}*(?=$self->{lb_AL})}osx, NO_BREAK];

# LB30 - Withdrawn

# LB31
    # ALL ÷
    push @rules, [qr{\G.(?=.)}osx, ALLOWED];
    # ÷ ALL
    push @rules, [qr{\G.(?=.)}osx, ALLOWED];

    $self->{_rules} = \@rules;
}

1;
