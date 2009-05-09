use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 2 }

dotest('fr', 'fr.ea', Context => 'EASTASIAN');
dotest('fr', 'fr', Context => 'EASTASIAN', SizingMethod => 'NARROWAL');

1;

