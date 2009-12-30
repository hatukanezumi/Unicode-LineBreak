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
our $VERSION = '0.005.1';

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

__END__

=head1 NAME

Unicode::GCString - String as Sequence of UAX #29 Grapheme Clusters

=head1 SYNOPSIS

    use Unicode::GCString;
    $gcstring = Unicode::GCString->new($string);
    
=head1 DESCRIPTION

Unicode::GCString treats Unicode string as a sequence of
I<extended grapheme clusters> defined by Unicode Standard Annex #29 [UAX #29].

B<Grapheme cluster> is a sequence of Unicode character(s) that consists of one
B<grapheme base> and optional B<grapheme extender> and/or
B<prepend character>.  It is close in that people consider as I<character>.

=head2 Public Interface

=head3 Constructors

=over 4

=item new (STRING, [LINEBREAK])

I<Constructor>.
Create new grapheme cluster string (Unicode::GCString object) from
Unicode string STRING.
Optional L<Unicode::LineBreak> object LINEBREAK controls breaking features.

=item copy

I<Copy constructor>.
Create a copy of grapheme cluster string.
Next position of new string is set at beginning.

=back

=head3 Sizes

=over 4

=item chars

I<Instance method>.
Returns number of Unicode characters grapheme cluster string includes,
i.e. length as Unicode string.

=item columns

I<Instance method>.
Returns total number of columns of grapheme clusters
defined by built-in character database.
For more details see L<Unicode::LineBreak/DESCRIPTION>.

=item length

I<Instance method>.
Returns number of grapheme clusters contained in grapheme cluster string.

=back

=head3 Operations as String

=over 4

=item as_string

=item C<">OBJECTC<">

I<Instance method>.
Convert grapheme cluster string to Unicode string explicitly.

=item cmp (STRING)

=item STRING C<cmp> STRING

I<Instance method>.
Compare strings.  There are no oddities.
One of each STRING may be Unicode string.

=item concat (STRING)

=item STRING C<.> STRING

I<Instance method>.
Concatenate STRINGs.  One of each STRING may be Unicode string.
Note that number of columns (see columns()) or grapheme clusters
(see length()) of resulting string is not always equal to sum of both
strings.
Next position of new string is that set on left value.

=item join ([STRING, ...])

I<Instance method>.
Join STRINGs inserting grapheme cluster string.
Any of STRINGs may be Unicode string.

=item substr (OFFSET, [LENGTH, [REPLACEMENT]])

I<Instance method>.
Returns substring of grapheme cluster string.
OFFSET and LENGTH are based on grapheme clusters.
If REPLACEMENT is specified, substring is replaced by it.

=back

=head3 Operations as Sequence of Grapheme Clusters

=over 4

=item as_array

=item C<@{>OBJECTC<}>

=item as_arrayref

I<Instance method>.
Convert grapheme cluster string to an array of grapheme clusters.

=item eos

I<Instance method>.
Test if current position is at end of grapheme cluster string.

=begin comment

=item flag ([OFFSET, [VALUE]])

I<Instance method>.
Get or set flag value of OFFEST-th grapheme cluster.
If OFFSET was not specified, returns flag value of next grapheme cluster.
Flag value is an non-zero integer not greater than 255 and initially is 0.

=end comment

=item item ([OFFSET])

I<Instance method>.
Returns OFFSET-th grapheme cluster.
If OFFSET was not specified, returns next grapheme cluster.

=begin comment

=item lbclass ([OFFSET])

I<Undocumented>.

=end comment

=begin comment

=item lbclass_ext ([OFFSET])

I<Undocumented>.

=end comment

=item next

=item C<E<lt>>OBJECTC<E<gt>>

I<Instance method>, iterative.
Returns next grapheme cluster and increment next position.

=item pos ([OFFSET])

I<Instance method>.
If optional OFFSET is specified, set next position by it.
Returns next position of grapheme cluster string.

=back

=head1 CAVEAT

=over 4

=item *

On Perl around 5.10.1, implicit conversion from Unicode::GCString object to
Unicode string sometimes let C<"utf8_mg_pos"> cache be confused.

For example, instead of doing

    $sub = substr($gcstring, $i, $j);

do

    $sub = substr("$gcstring", $i, $j);

    $sub = substr($gcstring->as_string, $i, $j);

=item *

This module implements I<default> algorithm for determining grapheme cluster
boundaries.  Tailoring mechanism has not been supported yet.

=back

=head1 VERSION

Consult $VERSION variable.

Development versions of this module may be found at 
L<http://hatuka.nezumi.nu/repos/Unicode-LineBreak/>.

=head1 SEE ALSO

[UAX #29]
Mark Davis (2009).
I<Unicode Standard Annex #29: Unicode Text Segmentation>, Revision 15.
L<http://www.unicode.org/reports/tr29/>.

=head1 AUTHOR

Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>

=head1 COPYRIGHT

Copyright (C) 2009 Hatuka*nezumi - IKEDA Soji.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
