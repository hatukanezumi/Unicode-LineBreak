use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 5 }

dotest('ecclesiazusae', 'ecclesiazusae');
dotest('ecclesiazusae', 'ecclesiazusae.ColumnsMax', UrgentBreaking => 'FORCE');
dotest('ecclesiazusae', 'ecclesiazusae.CharactersMax', CharactersMax => 79);
dotest('ecclesiazusae', 'ecclesiazusae.ColumnsMin',
       ColumnsMin => 7, ColumnsMax => 66, UrgentBreaking => 'FORCE');

eval {
    dotest('ecclesiazusae', 'ecclesiazusae', UrgentBreaking => 'CROAK');
};
ok($@ =~ /^Excessive line was found/, 'CROAK');

1;

