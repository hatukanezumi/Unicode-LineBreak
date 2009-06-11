use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 2 }

dotest('fr', 'fr.ea', Context => 'EASTASIAN');
dotest('fr', 'fr', Context => 'EASTASIAN',
       TailorEA => [AMBIGUOUS_ALPHABETIC() => EA_N()]);

1;

