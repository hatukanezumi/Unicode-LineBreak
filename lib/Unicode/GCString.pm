#-*-perl-*-

package Unicode::GCString;
require 5.008;

=encoding utf-8

=head1 NAME

Unicode::GCString - String as Sequence of UAX #29 Grapheme Clusters

=head1 SYNOPSIS

    use Unicode::GCString;
    $gcstr = Unicode::GCString($str);
    
=head1 DESCRIPTION

Unicode::GCString treats Unicode string as a sequence of
extended grapheme clusters defined by Unicode Standard Annex #29 [UAX #29].

B<Grapheme cluster> is a sequence of Unicode character(s) that consists of one
B<grapheme base> and optional B<grapheme extender> and/or
B<prepend character>.  It is close in that people consider as I<character>.

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
our $VERSION = '0.001';

=head2 Public Interface

=cut

use overload 
    '""' => \&as_string,
    '.=' => \&append,
    '.' => \&concat,
    '<>' => \&next_string;

=head3 Constructor

=over 4

=item new (STRING, [LINEBREAK])

I<Constructor>.
Create new Unicode::GCString object from Unicode string STRING.
Optional Unicode::LineBreak object LINEBREAK controls breaking features.

=back

=cut

# ->new (STRING, [LINEBREAK])
sub new {
    my $class = shift;
    my $str = shift;
    my $lbobj = shift || Unicode::LineBreak->new();
    my ($length, $pos);
    my @str = ();

    unless (defined $str and length $str) {
	$str = '';
    } elsif ($str =~ /[^\x00-\x7F]/s and !Encode::is_utf8($str)) {
        croak "Unicode string must be given.";
    }

    $length = length $str;
    $pos = 0;
    while ($pos < $length) {
	my ($glen, $gcol, $lbc) = $lbobj->gcinfo($str, $pos);
	push @str, [substr($str, $pos, $glen), $gcol, $lbc];
	$pos += $glen;
    }
    bless {
	lb => $lbobj,
	pos => 0,
	str => \@str,
    }, $class;
}

=head3 Operations as String

=over 4

=item append (STRING)

=item OBJECT C<.=> STRING

I<Instance method>.
Append STRING.  Grapheme cluster string is modified.
STRING may be either Unicode string or grapheme cluster string.

=back

=cut

# ->append (STRING)
sub append {
    my $self = shift;
    my $str = shift;
    $str = __PACKAGE__->new($self->{lb}, $str) unless ref $str;
    push @{$self->{str}}, @{$str->{str}};
    $self;
}

=over 4

=item as_string

=item C<">OBJECTC<">

I<Instance method>.
Convert grapheme cluster string to Unicode string.

=back

=cut

# ->as_string
sub as_string {
    my $self = shift;
    join '', map {$_->[0]} @{$self->{str}};
}

=over 4

=item columns

I<Instance method>.
Returns total number of columns of grapheme clusters string
defined by built-in character database.

=back

=cut

sub columns {
    my $self = shift;
    my $cols = 0;
    foreach my $c (@{$self->{str}}) {
	$cols += $c->[1];
    }
    $cols;
}

=over 4

=item concat (STRING)

=item STRING C<.> STRING

I<Instance method>.
Concatenate STRINGs then create new grapheme cluster string.
One of each STRING may be Unicode string.

=back

=cut

# ->concat (STRING)
sub concat {
    my $self = shift;
    my $str = shift;
    my $obj;
    $str = __PACKAGE__->new($self->{lb}, $str) unless ref $str;
    if (shift) {
	if (ref $str) {
	    $obj = $str->copy();
	    $obj->{lb} = $self->{lb};
	} else {
	    $obj = __PACKAGE__->new($self->{lb}, $str);
	}
	$str = $self;
    } else {
	$obj = $self->copy();
	$str = __PACKAGE__->new($self->{lb}, $str) unless ref $str;
    } 
    push @{$obj->{str}}, @{$str->{str}};
    $obj->{pos} = 0;
    $obj;
}

=over 4

=item copy

I<Copy constructor>.
Create a copy of grapheme cluster string.

=back

=cut

sub copy {
    my $self = shift;

    my $obj = __PACKAGE__->new($self->{lb});
    $obj->{pos} = $self->{pos};
    push @{$obj->{str}}, @{$self->{str}};
    $obj;
}

=over 4

=item length

I<Instance method>.
Returns number of grapheme clusters contained in grapheme cluster string.

=back

=cut

sub length {
    scalar @{shift->{str}};
}

=over 4

=item substr (INDEX, [LEN])

I<Instance method>.
Returns substring of grapheme cluster string.

=back

=cut

sub substr {
    my $self = shift;
    my $index = shift || 0;
    my $len = shift;
    $len = $#{$self->{str}} - $index + 1 unless defined $len;

    my $obj = $self->copy;
    $obj->{str} = [@{$obj->{str}}[$index..$index+$len-1]];
    $obj->{pos} = 0;
    $obj;
}

=head3 Operations as Sequence of Grapheme Clusters

=over 4

=item next

I<Instance method>, iterative.
Returns information of next grapheme cluster
as an array reference [STR, COLS, CLASS].

=back

=cut

sub next {
    my $self = shift;
    return undef if scalar $self->{str} <= $self->{pos};
    $self->{str}->[$self->{pos}++];
}

=over 4

=item next_string

=item C<E<lt>>OBJECTC<E<gt>>

I<Instance method>, iterative.
Returns next grapheme cluster as an Unicode string.

=back

=cut

sub next_string {
    my $self = shift;
    return undef if scalar $self->{str} <= $self->{pos};
    $self->{str}->[$self->{pos}++]->[0];
}

=over 4

=item reset

I<Instance method>.
Reset next position of grapheme cluster string.

=back

=cut

sub reset {
    my $self = shift;
    $self->{pos} = 0;
    $self;
}

=over 4

=item rest

I<Instance method>.
Returns rest of grapheme cluster string as array of array references
[STR, COLS, CLASS].

=back

=cut

sub rest {
    my $self = shift;
    @{$self->{str}}[$self->{pos}..$#{$self->{str}}];
}

=over 4

=item rest_string

I<Instance method>.
Returns rest of grapheme cluster string as Unicode string.

=back

=cut

sub rest_string {
    my $self = shift;
    join '', grep {$_->[0]} @{$self->{str}}[$self->{pos}..$#{$self->{str}}];
}

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

1;
