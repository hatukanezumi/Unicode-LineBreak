#-*-perl-*-

package Unicode::GCString;
require 5.008;

=encoding utf-8

=cut

### Pragmas:
use strict;
use warnings;
use vars qw($VERSION @EXPORT_OK @ISA);

### Exporting:
use Exporter;
our @EXPORT_OK = qw();
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);

### Inheritance:
our @ISA = qw(Exporter);

### Other modules:
use Unicode::LineBreak;

### Globals

# The package version
our $VERSION = '2011.03';

use overload 
    '@{}' => \&as_arrayref,
    '${}' => \&as_scalarref,
    '""' => \&as_string,
    '.' => \&concat,
    #XXX'.=' => \&concat, #FIXME:segfault
    'cmp' => \&cmp,
    '<>' => \&next,
    ;

sub as_arrayref {
    my @a = shift->as_array;
    return \@a;
}

1;
