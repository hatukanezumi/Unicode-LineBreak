# Note: Entries related to BK, CR, CM, LF, NL, SP aren't used by break().
our $RULES_MAP = [
    #BkCrLfNlSpOpClQuGlNsExSyIsPrPoNuAlIdInHyBaBbB2CbZwCmWjH2H3JlJvJt
    [M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,], # BK
    [M,M,P,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,], # CR
    [M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,], # LF
    [M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,], # NL
    [P,P,P,P,P,D,P,D,P,D,P,P,P,D,D,D,D,D,D,D,D,D,D,D,P,D,P,D,D,D,D,D,], # SP
    [P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,P,], # OP
    [P,P,P,P,P,D,P,I,P,P,P,P,P,I,I,D,D,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # CL
    [P,P,P,P,P,P,P,I,P,I,P,P,P,I,I,I,I,I,I,I,I,I,I,I,P,I,P,I,I,I,I,I,], # QU
    [P,P,P,P,P,I,P,I,P,I,P,P,P,I,I,I,I,I,I,I,I,I,I,I,P,I,P,I,I,I,I,I,], # GL
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,D,D,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # NS
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,D,D,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # EX
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,I,D,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # SY
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,I,I,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # IS
    [P,P,P,P,P,I,P,I,P,I,P,P,P,D,D,I,I,I,D,I,I,D,D,D,P,D,P,I,I,I,I,I,], # PR
    [P,P,P,P,P,I,P,I,P,I,P,P,P,D,D,I,I,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # PO
    [P,P,P,P,P,D,P,I,P,I,P,P,P,I,I,I,I,D,I,I,I,D,D,D,P,D,P,D,D,D,D,D,], # NU
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,I,I,D,I,I,I,D,D,D,P,D,P,D,D,D,D,D,], # AL
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,I,D,D,D,I,I,I,D,D,D,P,D,P,D,D,D,D,D,], # ID
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,D,D,D,I,I,I,D,D,D,P,D,P,D,D,D,D,D,], # IN
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,I,D,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # HY
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,D,D,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # BA
    [P,P,P,P,P,I,P,I,P,I,P,P,P,I,I,I,I,I,I,I,I,I,I,D,P,I,P,I,I,I,I,I,], # BB
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,D,D,D,D,I,I,D,P,D,P,D,P,D,D,D,D,D,], # B2
    [P,P,P,P,P,D,P,I,P,D,P,P,P,D,D,D,D,D,D,D,D,D,D,D,P,D,P,D,D,D,D,D,], # CB
    [P,P,P,P,P,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,P,D,D,D,D,D,D,D,], # ZW
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,D,D,D,D,D,I,I,D,D,D,P,D,P,D,D,D,D,D,], # CM
    [P,P,P,P,P,I,P,I,P,I,P,P,P,I,I,I,I,I,I,I,I,I,I,I,P,I,P,I,I,I,I,I,], # WJ
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,I,D,D,D,I,I,I,D,D,D,P,D,P,D,D,D,I,I,], # H2
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,I,D,D,D,I,I,I,D,D,D,P,D,P,D,D,D,D,I,], # H3
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,I,D,D,D,I,I,I,D,D,D,P,D,P,I,I,I,I,D,], # JL
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,I,D,D,D,I,I,I,D,D,D,P,D,P,D,D,D,I,I,], # JV
    [P,P,P,P,P,D,P,I,P,I,P,P,P,D,I,D,D,D,I,I,I,D,D,D,P,D,P,D,D,D,D,I,], # JT
];

