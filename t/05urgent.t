use strict;
use Test::More;
require "t/lb.pl";

BEGIN { plan tests => 4 }

dotest('aristophanes', 'aristophanes');
dotest('aristophanes', 'aristophanes.force', UrgentBreaking => 'FORCE');
dotest('aristophanes', 'aristophanes.CharactersMax', CharactersMax => 79);
dotest('aristophanes', 'aristophanes.ColumnsMin',
       ColumnsMin => 7, ColumnsMax => 66, UrgentBreaking => 'FORCE');

1;

