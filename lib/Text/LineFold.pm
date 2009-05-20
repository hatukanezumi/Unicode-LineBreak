#-*- perl -*-

package Text::LineFold;
require 5.008;

=encoding utf8

=head1 NAME

Text::LineFold - Line Folding for Plain Text

=head1 SYNOPSIS

    use Text::LineFold;
    $lf = Text::LineFold->new();
    
    $folded = $lf->fold($string, 'PLAIN');
    $unfolded = $lf->unfold($string, 'FIXED');

=head1 DESCRIPTION

Text::LineFold folds or unfolds lines of plain text.
As it mainly focuses on plain text e-mail messages,
RFC 3676 flowed format is also supported.

=cut

### Pragmas:
use strict;
use vars qw($VERSION @EXPORT_OK @ISA $Config);

### Exporting:
use Exporter;

### Inheritance:
our @ISA = qw(Exporter Unicode::LineBreak);

### Other modules:
use Carp qw(croak carp);
use Encode qw(is_utf8);
use MIME::Charset;
use Unicode::LineBreak qw(:all);

### Globals

### The package version, both in 1.23 style *and* usable by MakeMaker:
our $VERSION = '0.003';

### Public Configuration Attributes
our $Config = {
    ### %{$Unicode::LineBreak::Config},
    Charset => 'UTF-8',
    Language => 'XX',
    OutputCharset => undef,
};

### Privates

my %FORMAT_FUNCS = (
    'FIXED' => sub {
	my $self = shift;
	my $action = shift;
	my $str = shift;
	if ($action =~ /^so[tp]/) {
	    $self->{_} = {};
	    $self->{_}->{ColumnsMax} = $self->{ColumnsMax};
	    $self->config(ColumnsMax => 0) if $str =~ /^>/;
	} elsif ($action eq "") {
	    $self->{_}->{line} = $str;
	} elsif ($action eq "eol") {
	    return $self->{Newline};
	} elsif ($action =~ /^eo/) {
	    if (length $self->{_}->{line} and $self->{ColumnsMax}) {
		$str = $self->{Newline}.$self->{Newline};
	    } else {
		$str = $self->{Newline};
	    }
	    $self->config(ColumnsMax => $self->{_}->{ColumnsMax});
	    delete $self->{_};
	    return $str;
	}
	undef;
    },
    'FLOWED' => sub { # RFC 3676
	my $self = shift;
	my $action = shift;
	my $str = shift;
	if ($action eq 'sol') {
	    if ($self->{_}->{prefix}) {
		return $self->{_}->{prefix}.' '.$str if $self->{_}->{prefix};
	    } elsif ($str =~ /^(?: |From |>)/) {
		return ' '.$str;
	    }
	} elsif ($action =~ /^so/) {
	    $self->{_} = {};
	    if ($str =~ /^(>+)/) {
		$self->{_}->{prefix} = $1;
	    } else {
		$self->{_}->{prefix} = '';
		if ($str =~ /^(?: |From )/) {
		    return ' '.$str;
		}
	    }
	} elsif ($action eq "") {
	    $self->{_}->{line} = $str;
	} elsif ($action eq 'eol') {
	    $str = ' ' if length $str;
	    return $str.' '.$self->{Newline};
	} elsif ($action =~ /^eo/) {
	    if (length $self->{_}->{line} and !length $self->{_}->{prefix}) {
		$str = ' '.$self->{Newline}.$self->{Newline};
	    } else {
		$str = $self->{Newline};
	    }
	    delete $self->{_};
	    return $str;
	}
	undef;
    },
    'PLAIN' => sub {
	return $_[0]->{Newline} if $_[1] =~ /^eo/;
	undef;
    },
);


=head2 Public Interface

=over 4

=item new ([KEY => VALUE, ...])

I<Constructor>.
About KEY => VALUE pairs see config method.

=back

=cut

sub new {
    my $class = shift;
    my $self = Unicode::LineBreak->new();
    &config($self, @_);
    bless $self, $class;
}

=over 4

=item $self->config (KEY)

=item $self->config ([KEY => VAL, ...])

I<Instance method>.
Get or update configuration.  Following KEY => VALUE pairs may be specified.

=over 4

=item Charset => CHARSET

Character set that is used to encode string.
It may be string or instance of L<MIME::Charset> object.
Default is C<"UTF-8">.

=item Language => LANGUAGE

Along with Charset option, this may be used to define language/region
context.
Default is C<"XX">.
See also L<Unicode::LineBreak/Context> option.

=item OutputCharset => CHARSET

Character set that is used to encode result of fold()/unfold().
It may be string or instance of L<MIME::Charset> object.
If a special value C<"_UNICODE_"> is specified, result will be Unicode string.
Default is the value of Charset option.

=item CharactersMax

=item ColumnsMin

=item ColumnsMax

=item HangulAsAL

=item LegacyCM

=item Newline

=item NSKanaAsID

=item SizingMethod

=item UrgentBreaking

=item UserBreaking

See L<Unicode::LineBreak/Options>.

=back

=back

=cut

sub config {
    my $self = shift;
    my %params = @_;
    my @opts = qw{Charset Language OutputCharset};
    my @lbopts = qw{CharactersMax ColumnsMin ColumnsMax
			HangulAsAL LegacyCM Newline NSKanaAsID
			SizingMethod UrgentBreaking UserBreaking};

    # Get config.
    if (scalar @_ == 1) {
	foreach my $o (@opts) {
            if (uc $_[0] eq uc $o) {
		return $self->{$o};
            }
        }
	foreach my $o (@lbopts) {
            if (uc $_[0] eq uc $o) {
		return $self->SUPER::config($o);
            }
        }
	carp "No such option: $_[0]";
    }

    # Set config.
    my @o = ();
    OPTS: foreach my $k (keys %params) {
        my $v = $params{$k};
	foreach my $o (@opts) {
            if (uc $k eq uc $o) {
		$self->{$o} = $v;
		next OPTS;
            }
        }
	foreach my $o (@lbopts) {
	    if (uc $k eq uc $o) {
		push @o, $o => $v;
		last;
	    }
	}
    }
    Unicode::LineBreak::config($self, @o) if scalar @o;

    # Character set and language assumed.
    if (ref $self->{Charset}) {
        $self->{_charset} = $self->{Charset};
    } else {
        $self->{Charset} ||= $Config->{Charset};
        $self->{_charset} = MIME::Charset->new($self->{Charset});
    }
    $self->{Charset} = $self->{_charset}->as_string;
    my $ocharset = uc($self->{OutputCharset} || $self->{Charset});
    $ocharset = MIME::Charset->new($ocharset)
	unless ref $ocharset or $ocharset eq '_UNICODE_';
    unless ($ocharset eq '_UNICODE_') {
	$self->{_charset}->encoder($ocharset);
	$self->{OutputCharset} = $ocharset->as_string;
    }
    $self->{Language} = uc($self->{Language} || $Config->{Language});

    ## Context
    Unicode::LineBreak::config($self,
			       Context =>
			       getcontext(Charset => $self->{Charset},
					  Language => $self->{Language}));
}

=over 4

=item $self->fold (STRING, METHOD)

I<Instance method>.
fold() folds lines of string STRING and returns it.

Following options may be specified for METHOD argument.

=over 4

=item C<"FIXED">

Lines preceded by C<"E<gt>"> won't be folded.
Paragraphs are separated by empty line.

=item C<"FLOWED">

C<"Format=Flowed; DelSp=Yes"> formatting defined by RFC 3676.

=item C<"PLAIN">

Default method.

=back

By any options, surplus SPACEs at end of line are removed,
newline sequences are replaced by that specified by Newline option
and newline is appended at end of text if it does not exist.

=back

=cut

# Special breaking characters: VT, FF, NEL, LS, PS
my $special_break = qr/([\x{000B}\x{000C}\x{0085}\x{2028}\x{2029}])/os;

sub fold {
    my $self = shift;
    my $str = shift;
    return '' unless defined $str and length $str;
    my $method = uc(shift || '');

    ## Get format method.
    $self->SUPER::config(Format => $FORMAT_FUNCS{$method} ||
				   $FORMAT_FUNCS{'PLAIN'});
    ## Decode string.
    $str = $self->{_charset}->decode($str) unless is_utf8($str);

    ## Do folding.
    my $result = '';
    foreach my $s (split $special_break, $str) {
	if ($s =~ $special_break) {
	    $result .= $s;
	} else {
	    $result .= $self->break($str);
	}
    }

    ## Encode result.
    if ($self->{OutputCharset} eq '_UNICODE_') {
        return $result;
    } else {
        return $self->{_charset}->encode($result);
    }
}

=over 4

=item $self->unfold (STRING, METHOD)

Conjunct folded paragraphs of string STRING and returns it.

Following options may be specified for METHOD argument.

=over 4

=item C<"FIXED">

Default method.
Lines preceded by C<"E<gt>"> won't be conjuncted.
Treat empty line as paragraph separator.

=item C<"FLOWED">

Unfold C<"Format=Flowed; DelSp=Yes"> formatting defined by RFC 3676.

=begin comment

=item C<"OBSFLOWED">

Unfold C<"Format=Flowed> formatting defined by (obsoleted) RFC 2646
as well as possible.

=end comment

=back

=back

=cut

sub unfold {
    my $self = shift;
    my $str = shift;
    return '' unless defined $str and length $str;

    ## Get format method.
    my $method = uc(shift || 'FIXED');
    $method = 'FIXED' unless $method =~ /^(?:FIXED|FLOWED|OBSFLOWED)$/;

    ## Decode string and canonizalize newline.
    $str = $self->{_charset}->decode($str) unless is_utf8($str);
    $str =~ s/\r\n|\r/\n/g;

    ## Do unfolding.
    my $result = '';
    foreach my $s (split $special_break, $str) {
	if ($s eq '') {
	    next;
	} elsif ($s =~ $special_break) {
	    $result .= $s;
	    next;
	} elsif ($method eq 'FIXED') {
	    pos($s) = 0;
	    while ($s !~ /\G\z/cg) {
		if ($s =~ /\G\n/cg) {
		    $result .= $self->{Newline};
		} elsif ($s =~ /\G(.+)\n\n/cg) {
		    $result .= $1.$self->{Newline};
		} elsif ($s =~ /\G(>.*)\n/cg) {
		    $result .= $1.$self->{Newline};
		} elsif ($s =~ /\G(.+)\n(?=>)/cg) {
		    $result .= $1.$self->{Newline};
		} elsif ($s =~ /\G(.+?)( *)\n(?=(.))/cg) {
		    my ($l, $s, $n) = ($1, $2, $3);
		    $result .= $l;
		    if ($n eq ' ') {
			$result .= $self->{Newline};
		    } elsif (length $s) {
			$result .= $s;
		    } elsif (length $l) {
			my ($b_cls, $a_cls);
			my $i = length $l;
			do {
			    $i--;
			    $b_cls = $self->getlbclass(substr($l, $i));
			} while ($b_cls == LB_CM and 0 < $i);
			$b_cls = LB_AL if $b_cls == LB_CM or $b_cls == LB_SP;
			$a_cls = $self->getlbclass($n);
			$a_cls = LB_AL if $a_cls == LB_CM;

			if ($self->getlbrule($b_cls, $a_cls) == INDIRECT) {
			    $result .= ' ';
			}
		    }
		} elsif ($s =~ /\G(.+)\n/cg) {
		    $result .= $1.$self->{Newline};
		} elsif ($s =~ /\G(.+)/cg) {
		    $result .= $1.$self->{Newline};
		    last;
		}
	    }
	} elsif ($method eq 'FLOWED' or $method eq 'OBSFLOWED') {
	    my $prefix = undef;
	    pos($s) = 0;
	    while ($s !~ /\G\z/cg) {
		if ($s =~ /\G(>+) ?(.*?)( ?)\n/cg) {
		    my ($p, $l, $s) = ($1, $2, $3);
		    unless (defined $prefix) {
			$result .= $p.' '.$l;
		    } elsif ($p ne $prefix) {
			$result .= $self->{Newline};
			$result .= $p.' '.$l;
		    } else {
			$result .= $l;
		    }
		    unless (length $s) {
			$result .= $self->{Newline};
			$prefix = undef;
		    } else {
			$prefix = $p;
		    }
		} elsif ($s =~ /\G ?(.*?)( ?)\n/cg) {
		    my ($l, $s) = ($1, $2);
		    unless (defined $prefix) {
			$result .= $l;
		    } elsif ('' ne $prefix) {
			$result .= $self->{Newline};
			$result .= $l;
		    } else {
			$result .= $l;
		    }
		    unless (length $s) {
			$result .= $self->{Newline};
			$prefix = undef;
		    } else {
			$prefix = '';
		    }
		} elsif ($s =~ /\G ?(.*)/cg) {
		    $result .= $1.$self->{Newline};
		    last;
		}
	    }
	}
    }
    ## Encode result.
    if ($self->{OutputCharset} eq '_UNICODE_') {
        return $result;
    } else {
        return $self->{_charset}->encode($result);
    }
}

=head1 BUGS

Please report bugs or buggy behaviors to developer.  See L</AUTHOR>.

=head1 VERSION

Consult $VERSION variable.

Development versions of this module may be found at 
L<http://hatuka.nezumi.nu/repos/Unicode-LineBreak/>.

=head1 SEE ALSO

L<Unicode::LineBreak>, L<Text::Wrap>.

=head1 AUTHOR

Copyright (C) 2009 Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>.

This program is free software; you can redistribute it and/or modify it 
under the same terms as Perl itself.

=cut

1;
