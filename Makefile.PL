use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;

my $csubdir = 'sombok';
my $sombok_atleast_version = '2.0.6';
my $sombok_max_version = '2.99.99';
my $pkg_config = $ENV{'PKG_CONFIG'} || 'pkg-config';
my @args = ();
my $enable_libthai = 'yes';
my $bundled_sombok = 'no';
my $libthai;
my $enable_malloc_debug = 'no';

sub clean_subdirs {
    return <<EOF;
clean_subdirs:
\tif \$(TEST_F) $csubdir/Makefile; then cd $csubdir; \$(MAKE) distclean; fi
EOF
}

sub postamble {
    my $self = shift;
    my $args = join ' ', map {s/\'/\\\'/g; "'$_'"; } @args;
    my $tools = "CC='\$(CC)' CFLAGS='\$(CCFLAGS) \$(OPTIMIZE) \$(CCCDLFLAGS)'";
    $tools .= $self->{'FULL_AR'}? " AR='\$(FULL_AR)'":
	      ($self->{'AR'}? " AR='\$(AR)'": '');
    $tools .= $self->{'RANLIB'}? " RANLIB='\$(RANLIB)'": '';
    return <<EOF;
\$(MYEXTLIB): $csubdir/configure
\tcd $csubdir && \\
\t\$(SHELL) configure --disable-shared --disable-doc $tools $args
\tcd $csubdir && \$(MAKE)
EOF
}

foreach my $arg (@ARGV) {
    if ($arg =~ /^--(help|version)(=|\z)/) {
	chdir $csubdir;
	system("./configure $arg");
	exit;
    } elsif ($arg eq 'nolibthai' or $arg eq '--disable-libthai' or
	$arg eq '--enable-libthai=no') {
	$enable_libthai = 'no';
    } elsif ($arg eq '--with-bundled-sombok') {
	$bundled_sombok = 'yes';
    } elsif ($arg eq '--enable-malloc-debug') {
	$enable_malloc_debug = 'yes';
    } elsif ($arg =~ /^--/ or $arg =~ /^\w+=/) {
	push @args, $arg;
    } else {
	die "Unknown option $arg\n";
    }
}
my @opts = ();
$libthai = `$pkg_config --modversion libthai`;
chomp $libthai;
if ($libthai and $enable_libthai eq 'yes') {
    print "Use libthai $libthai\n";
    push @args, '--enable-libthai';
    push @opts, ('LIBS' => `$pkg_config --libs libthai`);
} else {
    push @args, '--disable-libthai';
}
if (system("$pkg_config --atleast-version=$sombok_atleast_version sombok")
    >> 8 or
    system("$pkg_config --max-version=$sombok_max_version sombok") >> 8) {
    $bundled_sombok = 'yes';
}
if ($enable_malloc_debug eq 'yes') {
    $bundled_sombok = 'yes';
    push @args, '--enable-malloc-debug';
    push @opts, ('DEFINE' => '-DMALLOC_DEBUG');
}
if ($bundled_sombok eq 'yes') {
    print "Use bundled sombok\n";
    push @opts, ('MYEXTLIB' => "$csubdir/.libs/libsombok\$(LIB_EXT)");
    push @opts, ('INC' => "-I$csubdir/include -I$csubdir");
    push @opts, ('depend' => { '$(OBJECT)' => '$(MYEXTLIB)' } );
} else {
    my $sombok = `$pkg_config --modversion sombok`;
    chomp $sombok;
    print "Use sombok $sombok\n";
    push @opts, ('LIBS' => `$pkg_config --libs sombok`);
    push @opts, ('INC' => `$pkg_config --cflags sombok`); 
}

WriteMakefile(
	'NO_META'	=> 1,
	'NAME'		=> 'Unicode::LineBreak',
	'ABSTRACT_FROM'	=> 'lib/Unicode/LineBreak.pod',
	'VERSION_FROM'	=> 'lib/Unicode/LineBreak.pm',
	'AUTHOR'	=> q{Hatuka*nezumi - IKEDA Soji <hatuka@nezumi.nu>},
	'LICENSE'	=> 'perl',
	'PREREQ_PM'	=> {
	    'Encode'		=> 1.98,
	    'MIME::Charset'	=> '1.006.2',
	    'Test::More'	=> '0.45',
	},
	@opts,
	'dist'		=> {
	    'PREOP'		=> "\$(PERL) -i -pe \'s/^(version:\\s+).*/\$\${1}\$(VERSION)/\' META.yml; \$(PERL) -i -pe \'s/^(%define version\\s+).*/\$\${1}\$(VERSION)/\' perl-Unicode-LineBreak.spec; cd $csubdir && \$(TOUCH) aclocal.m4 configure config.h.in Makefile.in",
	},
);
