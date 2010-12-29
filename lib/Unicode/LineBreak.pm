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
our $VERSION = '1.010';

### Public Configuration Attributes
our $Config = {
    CharactersMax => 998,
    ColumnsMin => 0,
    ColumnsMax => 76,
    Context => 'NONEASTASIAN',
    Format => "DEFAULT",
    HangulAsAL => 'NO',
    LegacyCM => 'YES',
    Newline => "\n",
    SizingMethod => 'DEFAULT',
    TailorEA => [],
    TailorLB => [],
    UrgentBreaking => 'NONBREAK',
    UserBreaking => [],
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

# Built-in custom breaking behaviors specified by C<UserBreaking>.
my $URIre = qr{
	       \b
	       (?:url:)?
	       (?:[a-z][-0-9a-z+.]+://|news:|mailto:)
	       [\x21-\x7E]+
}iox;
my %USER_BREAKING_FUNCS = (
    'NONBREAKURI' => [ $URIre, sub { ($_[1]) } ],
    # Breaking URIs according to CMOS:
    # 7.11 1-1: [/] ÷ [^/]
    # 7.11 2:   [-] ×
    # 6.17 2:   [.] ×
    # 7.11 1-2: ÷ [-~.,_?#%]
    # 7.11 1-3: ÷ [=&]
    # 7.11 1-3: [=&] ÷
    # Default:  ALL × ALL
    'BREAKURI' => [ $URIre,
		    sub {
			my @c = split m{
			    (?<=^url:) |
			    (?<=[/]) (?=[^/]) |
			    (?<=[^-.]) (?=[-~.,_?\#%=&]) |
			    (?<=[=&]) (?=.)
			}iox, $_[1];
			# Won't break punctuations at end of matches.
			while (2 <= scalar @c and $c[$#c] =~ /^[.:;,>]+$/) {
			    my $c = pop @c;
			    $c[$#c] .= $c;
			}
			@c;
		    }],
);

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
    my @nopts = qw(CharactersMax ColumnsMin ColumnsMax Context
		   HangulAsAL LegacyCM Newline);
    my @uopts = qw(Format SizingMethod
		   TailorEA TailorLB UrgentBreaking UserBreaking);
    my %nopts = map { (uc $_ => $_); } @nopts;
    my %uopts = map { (uc $_ => $_); } @uopts;

    # Get config.
    if (scalar @_ == 1) {
	my $k = shift;
	if ($uopts{uc $k}) {
	    return $self->{$uopts{uc $k}};
	} else {
	    return $self->_config($nopts{uc $k} || $k);
	}
    }

    # Set config.
    my %params = @_;
    my %copts = ();
    my %config = ();
    my $k;
    foreach $k (keys %params) {
	my $v = $params{$k};
	if ($uopts{uc $k}) {
	    $self->{$uopts{uc $k}} = $v;
	    $copts{$uopts{uc $k}} = $v;
	} else {
	    $config{$nopts{uc $k} || $k} = $v;
	}
    }

    ## Utility options.
    # Format method.
    if (defined $copts{Format}) {
	$config{Format} = $copts{Format};
    }
    # Sizing method
    if (defined $copts{SizingMethod}) {
	$config{SizingMethod} = $copts{SizingMethod};
    }
    # Urgent break
    if (defined $copts{UrgentBreaking}) {
	$config{UrgentBreaking} = $copts{UrgentBreaking};
    }
    # Custom break
    if (defined $copts{UserBreaking}) {
	$copts{UserBreaking} = [$copts{UserBreaking}]
	    unless ref $copts{UserBreaking} eq 'ARRAY';
	my @cf = ();
	foreach my $ub (@{$self->{UserBreaking}}) {
	    next unless defined $ub;
	    unless (ref $ub eq 'ARRAY') {
		$ub = $USER_BREAKING_FUNCS{uc $ub};
		next unless defined $ub;
	    }
	    my ($re, $func) = @{$ub};
	    push @cf, [qr{$re}o, $func];
	}
	$config{UserBreaking} = \@cf;
    }
    # Character classes
    if (defined $copts{TailorLB} or defined $copts{TailorEA}) {
	$copts{TailorLB} ||= $self->{TailorLB};
	$copts{TailorEA} ||= $self->{TailorEA};
	my %map = ();
	foreach my $o (qw{TailorLB TailorEA}) {
	    $copts{$o} = [@{$Config->{$o}}]
		unless defined $copts{$o} and ref $copts{$o} eq 'ARRAY';
	    my @v = @{$copts{$o}};
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
	$config{_map} = \@map;
    }

    $self->_config((%config)) if scalar keys %config;
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

sub preprocess ($$$) {
    my $self = shift;
    my $user_funcs = shift;
    my $str = shift;

    unless (defined $str and length $str) {
	$str = '';
    }

    my @ret = ();
    while (length $str) {
	my $func;
	my ($s, $match, $post) = ($str, '', '');
	foreach my $ub (@{$user_funcs}) {
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

	push @ret, $s if length $s;

	# Break matched fragment.
	if (length $match) {
	    my $first = 1;
	    foreach my $s (&{$func}($self, $match)) {
		$s = Unicode::GCString->new($s, $self);
		my $length = $s->length;
		if ($length) {
		    if (!$first) {
			$s->flag(0, BREAK_BEFORE);
		    }
		    for (my $i = 1; $i < $length; $i++) {
			$s->flag($i, PROHIBIT_BEFORE);
		    }
		    push @ret, $s;
		}
		$first = 0;
	    }
	}
    }

    @ret;
}

1;
