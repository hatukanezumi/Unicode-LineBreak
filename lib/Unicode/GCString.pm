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
use Carp qw(croak carp);
use Unicode::LineBreak;

### Globals

# The package version
our $VERSION = '0.003_01';

use overload 
    '@{}' => \&as_arrayref,
    '""' => \&as_string,
    '.' => \&concat,
    '.=' => \&concat,
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

B<WARNING: This module is alpha version therefore includes some bugs and unstable features.>

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

=head3 Operations as String

=over 4

=item as_string

=item C<">OBJECTC<">

I<Instance method>.
Convert grapheme cluster string to Unicode string.

=item columns

I<Instance method>.
Returns total number of columns of grapheme clusters string
defined by built-in character database.
For more details see L<Unicode::LineBreak/DESCRIPTION>.

=item concat (STRING)

=item STRING C<.> STRING

=item STRING C<.=> STRING

I<Instance method>.
Concatenate STRINGs.  One of each STRING may be Unicode string.
Note that number of columns (see columns()) or grapheme clusters
(see lenbgth()) of resulting string is not always equal to sum of both
strings.
Next position of new string is that set on left value.

=item length

I<Instance method>.
Returns number of grapheme clusters contained in grapheme cluster string.

=item substr (OFFSET, [LENGTH])

I<Instance method>.
Returns substring of grapheme cluster string.
OFFSET and LENGTH are based on grapheme clusters.

=back

=head3 Operations as Sequence of Grapheme Clusters

=over 4

=item as_array

=item C<@{>OBJECTC<}>

=item as_arrayref

I<Instance method>.
Convert grapheme cluster string to an array of informations of grapheme
clusters.

=item eot

I<Instance method>.
Test if current position is at end of grapheme cluster string.

=begin comment

=item flag (INDEX, [VALUE])

I<Undocumented>.

=end comment

=item item ([OFFSET])

I<Instance method>.
Returns information of OFFSET-th grapheme cluster as array reference.
If OFFSET was not specified, returns information of next grapheme cluster.

=item next

I<Instance method>, iterative.
Returns information of next grapheme cluster as array reference.

=item prev

I<Instance method>.
Decrement position of grapheme cluster string.

=item reset

I<Instance method>.
Reset next position of grapheme cluster string.

=begin comment

=item rest

I<Instance method>.
B<Not implemented yet>.
Returns rest of grapheme cluster string.

=end comment

=back

=head1 VERSION

Consult $VERSION variable.

Development versions of this module may be found at 
L<http://hatuka.nezumi.nu/repos/Unicode-LineBreak/>.

=head1 SEE ALSO

[UAX #29]
Mark Davis (2009).
<Unicode Standard Annex #29: Unicode Text Segmentation>, Revision 15.
L<http://www.unicode.org/reports/tr29/>.

=head1 AUTHOR

Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>

=head1 COPYRIGHT

Copyright (C) 2009 Hatuka*nezumi - IKEDA Soji.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
