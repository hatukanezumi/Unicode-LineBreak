use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 3 }

dotest('aristophanes', 'aristophanes');
dotest('aristophanes', 'aristophanes.force', UrgentBreaking => 'FORCE');
dotest('aristophanes', 'aristophanes.chars', CharactersMax => 79);

1;

