use strict;
use Test::More;
require 't/lb.pl';

BEGIN { plan tests => 4 }

my $lb = Unicode::LineBreak->new(Context => 'EASTASIAN');

is(Unicode::GCString->new(Encode::decode('iso-8859-1', "\xA0"), $lb)->lbc,
   Unicode::LineBreak::LB_GL());
is(Unicode::GCString->new(Encode::decode('iso-8859-1', "\xC2\xA0"), $lb)->lbc,
   Unicode::LineBreak::LB_AL());
is(Unicode::GCString->new(Encode::decode('iso-8859-1', "\xD7"), $lb)->columns,
   2);
is(Unicode::GCString->new(Encode::decode('iso-8859-1', "\xC3"), $lb)->columns,
   1);

### obsoleted functions
##foreach my $s (("\xA0", "\x{A0}", Encode::decode('iso-8859-1', "\xA0"),
##		)) {
##    is($lb->lbclass($s), Unicode::LineBreak::LB_GL());
##}
##is($lb->lbclass("\xC2\xA0"), Unicode::LineBreak::LB_AL());
##foreach my $s (("\xD7", "\x{D7}", Encode::decode('iso-8859-1', "\xD7"),
##		)) {
##    is($lb->eawidth($s), Unicode::LineBreak::EA_F());
##}
##is($lb->eawidth("\xC3\x97"), Unicode::LineBreak::EA_N());

