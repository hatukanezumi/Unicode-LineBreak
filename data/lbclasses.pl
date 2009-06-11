#-*- perl -*-

@LBCLASSES = qw{BK CR LF NL SP
OP CL QU GL NS EX SY IS PR PO NU AL ID IN HY BA BB B2 CB ZW CM WJ
H2 H3 JL JV JT
SG AI SA XX};
#$OMIT = qr{BK|CM|CR|LF|NL|SP|AI|SA|SG|XX|...};
$OMIT = qr{AI|SA|SG|XX|...};
@LBCLASSES = (grep(!/$OMIT/, @LBCLASSES), grep(/$OMIT/, @LBCLASSES));
@EAWIDTHS = qw{Z Na N A W H F};
@SCRIPTS = qw(Common Inherited);

1;

