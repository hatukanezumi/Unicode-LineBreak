use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;

my $csubdir = 'sombok';
my $sombok_atleast_version = '2011.3';
my $pkg_config = $ENV{'PKG_CONFIG'} || 'pkg-config';
my @args = ();
my $enable_libthai = 'yes';
my $bundled_sombok = 'no';
my $libthai;
my $enable_malloc_debug = 'no';

sub top_targets {
    my $inherited = shift->SUPER::top_targets(@_);
    if ($libthai and $enable_libthai eq 'yes') {
	$inherited =~ s{^(all ::.*?)\n.*?$}{<<EOF}em;
$1
\t\$(NOECHO) \$(MAKE) test TEST_FILES=t/07sea.t >/dev/null || \\
\t( \$(ECHO) "Your libthai is broken.  Rebuild it then try again."; \\
\texit 1 )
EOF
    }
    $inherited;
}

sub clean_subdirs {
    return <<EOF;
clean_subdirs:
\tif \$(TEST_F) $csubdir/Makefile; then cd $csubdir; \$(MAKE) distclean; fi
EOF
}

sub postamble {
    my $args = join ' ', map {s/\'/\\\'/g; "'$_'"; } @args;
    return <<EOF;
\$(MYEXTLIB): $csubdir/configure
\tcd $csubdir && \\
\t\$(SHELL) configure --disable-shared --enable-static $args \\
\tCC='\$(CC)' CFLAGS='\$(CCFLAGS) \$(OPTIMIZE) \$(CCCDLFLAGS)'
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
    >> 8) {
    $bundled_sombok = 'yes';
}
if ($enable_malloc_debug eq 'yes') {
    $bundled_sombok = 'yes';
    push @args, '--enable-malloc-debug';
    push @opts, ('DEFINE' => '-DMALLOC_DEBUG');
}
if ($bundled_sombok eq 'yes') {
    push @opts, ('MYEXTLIB' => "$csubdir/.libs/libsombok\$(LIB_EXT)");
    push @opts, ('INC' => "-I$csubdir/include -I$csubdir");
    push @opts, ('depend' => { '$(OBJECT)' => '$(MYEXTLIB)' } );
} else {
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
	    'PREOP'		=> "cd $csubdir && \$(TOUCH) aclocal.m4 configure config.h.in Makefile.in",
	},
);
