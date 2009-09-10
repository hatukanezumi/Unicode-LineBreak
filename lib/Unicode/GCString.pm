#-*-perl-*-

package Unicode::GCString;
require 5.008;

=encoding utf-8

=head1 NAME

Unicode::GCString - String as Sequence of UAX #29 Grapheme Clusters

=head1 SYNOPSIS

    use Unicode::GCString;
    $gcstring = Unicode::GCString->new($string);
    
=head1 DESCRIPTION

B<WARNING: This module is pre-alpha version therefore includes many bugs and unstable features.>

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
our $VERSION = '0.002_01';

=head2 Public Interface

=cut

use overload 
    #XXX'""' => \&as_string,
    #XXX'.=' => \&append,
    #XXX'.' => \&concat,
    '<>' => \&next;

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

    if (ref $str) {
	$str = $str->as_string;
    }
    unless (defined $str and length $str) {
	$str = '';
    } elsif ($str =~ /[^\x00-\x7F]/s and !Encode::is_utf8($str)) {
        croak "Unicode string must be given.";
    }

    my @str = ();
    while (length $str) {
	my $func;
	my ($s, $match, $post) = ($str, '', '');
	foreach my $ub (@{$lbobj->{_user_breaking_funcs}}) {
	    my ($re, $fn) = @{$ub};
	    if ($str =~ /$re/) {
		if (length $& and length $` < length $s) { #`
		    ($s, $match, $post) = ($`, $&, $'); #'`
		    $func = $fn;
		}
	    }
	}
	if (length $match) {
	    $str = $post;
	} else {
	    $s = $str;
	    $str = '';
	}
	my $length = length $s;
	my $pos = 0;
	while ($pos < $length) {
	    my ($glen, $gcol, $lbc) = $lbobj->gcinfo($s, $pos);
	    push @str, [substr($s, $pos, $glen), $gcol, $lbc];
	    $pos += $glen;
	}
	if (length $match) {
	    my ($glen, $gcol, $lbc);
	    my @s = ();
	    foreach my $s (&{$func}($lbobj, $match)) {
		my $length = length $s;
		my $pos = 0;
		my @g = ();
		while ($pos < $length) {
		    ($glen, $gcol, $lbc) = $lbobj->gcinfo($s, $pos);
		    push @g, [substr($s, $pos, $glen), $gcol, $lbc,
			      (scalar @s && !scalar @g), scalar @g];
		    $pos += $glen;
		}
		if ($lbc == Unicode::LineBreak::LB_SP()) {
		    my $sp = pop @g;
		    push @s, @g;
		    push @s, [$sp, $gcol, $lbc];
		} else {
		    push @s, @g;
		}
	    }
	    push @str, @s;
	}
    }

    bless {
	lbobj => $lbobj,
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
    $str = __PACKAGE__->new($str, $self->{lbobj}) unless ref $str;

    my $c = '';
    $c = ${pop @{$self->{str}}}[0] if scalar @{$self->{str}};
    $c .= ${shift @{$str->{str}}}[0] if scalar @{$str->{str}};
    push @{$self->{str}}, @{__PACKAGE__->new($c, $self->{lbobj})->{str}}
	if length $c;
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
    $str = __PACKAGE__->new($str, $self->{lbobj}) unless ref $str;
    if (shift) {
	if (ref $str) {
	    $obj = $str->copy();
	    $obj->{lbobj} = $self->{lbobj};
	} else {
	    $obj = __PACKAGE__->new($str, $self->{lbobj});
	}
	$str = $self;
    } else {
	$obj = $self->copy();
	$str = __PACKAGE__->new($str, $self->{lbobj}) unless ref $str;
    } 

    my $c = '';
    $c = ${pop @{$obj->{str}}}[0] if scalar @{$obj->{str}};
    $c .= ${shift @{$str->{str}}}[0] if scalar @{$str->{str}};
    push @{$obj->{str}}, @{__PACKAGE__->new($c, $self->{lbobj})->{str}}
	if length $c;
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

    my $obj = __PACKAGE__->new('', $self->{lbobj});
    push @{$obj->{str}}, @{$self->{str}};
    $obj->{pos} = $self->{pos};
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

=item eot

I<Instance method>.
Test if current position is at end of grapheme cluster string.

=back

=cut

sub eot {
    my $self = shift;
    return scalar @{$self->{str}} <= $self->{pos};
}

=over 4

=item next

I<Instance method>, iterative.
Returns information of next grapheme cluster
as array reference.

=back

=cut

sub next {
    my $self = shift;
    return undef if scalar @{$self->{str}} <= $self->{pos};
    $self->{str}->[$self->{pos}++];
}

=over 4

=item prev

Decrement position of grapheme cluster string.

=back

=cut

sub prev {
    my $self = shift;

    $self->{pos}-- if 0 < $self->{pos};
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
Returns rest of grapheme cluster string.

=back

=cut

sub rest {
    my $self = shift;

    my $obj = __PACKAGE__->new('', $self->{lbobj});
    push @{$obj->{str}}, @{$self->{str}}[$self->{pos}..$#{$self->{str}}];
    $obj;
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
