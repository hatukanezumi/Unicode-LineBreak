#-*- perl -*-

package Unicode::LineBreak;
require 5.008;

### Pragmas:
use strict;
use warnings;
use vars qw($VERSION @EXPORT_OK @ISA $Config);

### Exporting:
use Exporter;
our @EXPORT_OK = qw(UNICODE_VERSION context);
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);

### Inheritance:
our @ISA = qw(Exporter);

### Other modules:
use Carp qw(croak carp);
use Encode qw(is_utf8);
use MIME::Charset;
use Unicode::GCString;

### Globals

### The package version
our $VERSION = '2011.002_19';

### Public Configuration Attributes
our $Config = {
    BreakIndent => 'YES',
    CharactersMax => 998,
    ColumnsMin => 0,
    ColumnsMax => 76,
    ComplexBreaking => 'YES',
    Context => 'NONEASTASIAN',
    Format => "SIMPLE",
    HangulAsAL => 'NO',
    LegacyCM => 'YES',
    Newline => "\n",
    #Prep => undef,
    SizingMethod => 'UAX11',
    TailorEA => [],
    TailorLB => [],
    #UrgentBreaking => undef,
};
eval { require Unicode::LineBreak::Defaults; };

### Exportable constants
use Unicode::LineBreak::Constants;
use constant 1.01;
my $package = __PACKAGE__;
my @consts = grep { s/^${package}::(\w\w+)$/$1/ } keys %constant::declared;
push @EXPORT_OK, @consts;
push @{$EXPORT_TAGS{'all'}}, @consts;

### Load XS module
require XSLoader;
XSLoader::load('Unicode::LineBreak', $VERSION);

### Load dynamic constants
foreach my $prop (qw(EA GB LB SC)) {
    my $idx = 0;
    foreach my $val (_propvals($prop)) {
	no strict;
	my $const = "${prop}_${val}";
	*{$const} = eval "sub { $idx }";
	push @EXPORT_OK, $const;
	push @{$EXPORT_TAGS{'all'}}, $const;
	$idx++;
    }
}

### Privates
my $EASTASIAN_CHARSETS = qr{
    ^BIG5 |
    ^CP9\d\d |
    ^EUC- |
    ^GB18030 | ^GB2312 | ^GBK |
    ^HZ |
    ^ISO-2022- |
    ^KS_C_5601 |
    ^SHIFT_JIS
}ix;

my $EASTASIAN_LANGUAGES = qr{
    ^AIN |
    ^JA\b | ^JPN |
    ^KO\b | ^KOR |
    ^ZH\b | ^CHI
}ix;

use overload
    '%{}' => \&as_hashref,
    '${}' => \&as_scalarref,
    '""' => \&as_string,
    ;

sub new {
    my $class = shift;

    my $self = __PACKAGE__->_new();
    $self->config((%$Config));
    $self->config(@_);
    $self;
}

sub config ($@) {
    my $self = shift;

    # Get config.
    if (scalar @_ == 1) {
	my $k = shift;
	if (uc $k eq uc 'UserBreaking') {
	    return $self->_config('Prep');
	} elsif (uc $k eq uc 'TailorEA') {
	    return $self->{'TailorEA'};
	} elsif (uc $k eq uc 'TailorLB') {
	    return $self->{'TailorLB'};
	} else {
	    return $self->_config($k);
	}
    }

    # Set config.
    my @config = ();
    while (0 < scalar @_) {
	my $k = shift;
	my $v = shift;
	if (uc $k eq uc 'UserBreaking') {
	    push @config, 'Prep' => undef;
	    if (! defined $v) {
		;
	    } elsif (ref $v eq 'ARRAY') {
		push @config, map { ('Prep' => $_) } @{$v};
	    } else {
		push @config, 'Prep' => $v;
	    }
	} elsif (uc $k eq uc 'TailorLB') {
	    $self->{'TailorLB'} = $v;
	} elsif (uc $k eq uc 'TailorEA') {
	    $self->{'TailorEA'} = $v;
	} else {
	    push @config, $k => $v;
	}
    }

    # Character classes
    if (defined $self->{TailorLB} or defined $self->{TailorEA}) {
	my %map = ();
	foreach my $o (qw{TailorLB TailorEA}) {
	    $self->{$o} = [@{$Config->{$o}}]
		unless defined $self->{$o} and ref $self->{$o} eq 'ARRAY';
	    my @v = @{$self->{$o}};
	    while (scalar @v) {
		my $k = shift @v;
		my $v = shift @v;
		next unless defined $k and defined $v;
		if (ref $k eq 'ARRAY') {
		    foreach my $c (@{$k}) {
			$map{$c} ||= [-1, -1];
			if ($o eq 'TailorLB') {
			    $map{$c}->[0] = $v;
			} else {
			    $map{$c}->[1] = $v;
			}
		    }
		} else {
		    $map{$k} ||= [-1, -1];
		    if ($o eq 'TailorLB') {
			$map{$k}->[0] = $v;
		    } else {
			$map{$k}->[1] = $v;
		    }
		}
	    }
	}
	my @map = ();
	my ($beg, $end) = (undef, undef);
	my $p;
	foreach my $c (sort {$a <=> $b} keys %map) {
	    unless ($map{$c}) {
		next;
	    } elsif (defined $end and $end + 1 == $c and
		     $p->[0] == $map{$c}->[0] and $p->[1] == $map{$c}->[1]) {
		$end = $c;
	    } else {
		if (defined $beg and defined $end) {
		    push @map, [$beg, $end, @{$p}];
		}
		$beg = $end = $c;
		$p = $map{$c};
	    }
	}
	if (defined $beg and defined $end) {
	    push @map, [$beg, $end, @{$p}];
	}
	push @config, '_map' => \@map;
    }

    $self->_config(@config) if scalar @config;
}

sub context (@) {
    my %opts = @_;

    my $charset;
    my $language;
    my $context;
    foreach my $k (keys %opts) {
	if (uc $k eq 'CHARSET') {
	    if (ref $opts{$k}) {
		$charset = $opts{$k}->as_string;
	    } else {
		$charset = MIME::Charset->new($opts{$k})->as_string;
	    }
	} elsif (uc $k eq 'LANGUAGE') {
	    $language = uc $opts{$k};
	    $language =~ s/_/-/;
	}
    }
    if ($charset and $charset =~ /$EASTASIAN_CHARSETS/) {
        $context = 'EASTASIAN';
    } elsif ($language and $language =~ /$EASTASIAN_LANGUAGES/) {
	$context = 'EASTASIAN';
    } else {
	$context = 'NONEASTASIAN';
    }
    $context;
}

1;
