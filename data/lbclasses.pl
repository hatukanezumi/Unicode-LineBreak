#-*- perl -*-

@LBCLASSES = qw{BK CR LF NL SP
OP CL QU GL NS EX SY IS PR PO NU AL ID IN HY BA BB B2 CB ZW CM WJ
H2 H3 JL JV JT
SG AI SA XX};
# Addendum after 5.1.0.
if ($unicode_version) {
    my $uv = sprintf '%03d%03d%03d', split /\D+/, $unicode_version;
    push @LBCLASSES, 'CP' if '005002000' le $uv; # 5.2.0beta (UAX #14 rev. 23)
} else {
    push @LBCLASSES, 'CP';
}
#$OMIT = qr{BK|CM|CR|LF|NL|SP|AI|SA|SG|XX|...};
$OMIT = qr{AI|SA|SG|XX|...};
@LBCLASSES = (grep(!/$OMIT/, @LBCLASSES), grep(/$OMIT/, @LBCLASSES));
@EAWIDTHS = qw{Z Na N A W H F};
@SCRIPTS = qw(Common Inherited);

1;

