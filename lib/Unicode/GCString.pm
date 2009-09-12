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
    #XXX'<>' => \&next,
    ;

# ->new (STRING, [LINEBREAK])
sub new {
    my $class = shift;
    my $str = shift;
    my $lbobj = shift || Unicode::LineBreak->new();

    if (ref $str) {
	$str = $str->as_string;
    }
    unless (defined $str and CORE::length $str) {
	$str = '';
    } elsif ($str =~ /[^\x00-\x7F]/s and !Encode::is_utf8($str)) {
        croak "Unicode string must be given.";
    }

    my $ret = __PACKAGE__->_new('');
    while (CORE::length $str) {
	my $func;
	my ($s, $match, $post) = ($str, '', '');
	foreach my $ub (@{$lbobj->{_user_breaking_funcs}}) {
	    my ($re, $fn) = @{$ub};
	    if ($str =~ /$re/) {
		if (CORE::length $& and CORE::length $` < CORE::length $s) { #`
		    ($s, $match, $post) = ($`, $&, $'); #'`
		    $func = $fn;
		}
	    }
	}
	if (CORE::length $match) {
	    $str = $post;
	} else {
	    $s = $str;
	    $str = '';
	}

	# Break unmatched fragment.
	my %sa_break;
	if (CORE::length $s) {
	    %sa_break = map { ($_ => 1); }
	    Unicode::LineBreak::SouthEastAsian::break_indexes($s);
	    $s = __PACKAGE__->_new($s, $lbobj);
	    my $pos = 0;
	    my $length = $s->length;
	    my @s = @{$s};
	    for (my $i = 0; $i < $length; $i++) {
		my $item = $s[$i];
		if ($item->[2] == Unicode::LineBreak::LB_SA()) {
		    $s->flag($i,
			     $sa_break{$pos}?
			     Unicode::LineBreak::BREAK_BEFORE():
			     Unicode::LineBreak::PROHIBIT_BEFORE());
		}
		$pos += CORE::length $item->[0];
	    }
	    $ret .= $s;
	}

	# Break matched fragment.
	if (CORE::length $match) {
	    my $first = 1;
	    foreach my $s (&{$func}($lbobj, $match)) {
		$s = __PACKAGE__->_new($s, $lbobj);
		my $length = $s->length;
		if ($length) {
		    if (!$first) {
			$s->flag(0, Unicode::LineBreak::BREAK_BEFORE());
		    }
		    for (my $i = 1; $i < $length; $i++) {
			$s->flag($i, Unicode::LineBreak::PROHIBIT_BEFORE());
		    }
		    $ret .= $s;
		}
		$first = 0;
	    }
	}
    }

    $ret;
}

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

=item length

I<Instance method>.
Returns number of grapheme clusters contained in grapheme cluster string.

=item substr (INDEX, [LEN])

I<Instance method>.
B<Not yet implemented>.
Returns substring of grapheme cluster string.

=back

=head3 Operations as Sequence of Grapheme Clusters

=over 4

=item as_array

=item C<@{>OBJECTC<}>

=item as_arrayref

I<Instance method>.
Convert grapheme cluster string to an array of informations of grapheme
clusters.

=begin comment

=item eot

I<Instance method>.
B<Not implemented yet>.
Test if current position is at end of grapheme cluster string.

=end comment

=begin comment

=item flag (INDEX, [VALUE])

I<Undocumented>.

=end comment

=item item (INDEX)

I<Instance method>.
Returns information of INDEX-th grapheme cluster as array reference.

=begin comment

=item next

I<Instance method>, iterative.
B<Not implemented yet>.
Returns information of next grapheme cluster
as array reference.

=item prev

B<Not implemented yet>.
Decrement position of grapheme cluster string.

=item reset

I<Instance method>.
B<Not implemented yet>.
Reset next position of grapheme cluster string.

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
