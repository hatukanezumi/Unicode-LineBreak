use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;

my $csubdir = 'linebreak-c';
my $linebreak_atleast_version = '1.10.0';
my $pkg_config = $ENV{'PKG_CONFIG'} || 'pkg-config';
my @args = ();
my $enable_libthai = 'yes';
my $bundled_linebreak = 'no';
my $libthai;

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
    if ($^O eq 'MSWin32') {
	return <<EOF;
\$(MYEXTLIB): $csubdir/Makefile.mingw
\tcd $csubdir && \\
\t\$(MAKE) -f Makefile.mingw all CC=\"\$(CC)\" CFLAGS=\"\$(CCFLAGS) \$(OPTIMIZE)\" AR=\"\$(AR)\"
EOF
    } else {
	return <<EOF;
\$(MYEXTLIB): $csubdir/Makefile
\tcd $csubdir && \$(MAKE)
$csubdir/Makefile: $csubdir/configure
\tcd $csubdir && \\
\t./configure --disable-shared --enable-static $args \\
\tCC='\$(CC)' CFLAGS='\$(CCFLAGS) \$(OPTIMIZE) \$(CCCDLFLAGS)'
$csubdir/configure: $csubdir/configure.ac
\tcd $csubdir && autoreconf
EOF
    }
}

foreach my $arg (@ARGV) {
    if ($arg =~ /^--(help|version)(=|\z)/) {
	chdir $csubdir;
	system("./configure $arg");
	exit;
    } elsif ($arg eq 'nolibthai' or $arg eq '--disable-libthai' or
	$arg eq '--enable-libthai=no') {
	$enable_libthai = 'no';
    } elsif ($arg eq '--with-bundled-linebreak') {
	$bundled_linebreak = 'yes';
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
if (system("$pkg_config --atleast-version=$linebreak_atleast_version " .
	   "linebreak") >> 8) {
    $bundled_linebreak = 'yes';
}
if ($^O eq 'MSWin32') {
    push @opts, ('MYEXTLIB' => "$csubdir/lib/libinebreak\$(LIB_EXT)");
    push @opts, ('INC' => "-I$csubdir/include -I$csubdir");
} elsif ($bundled_linebreak eq 'yes') {
    push @opts, ('MYEXTLIB' => "$csubdir/.libs/libinebreak\$(LIB_EXT)");
    push @opts, ('INC' => "-I$csubdir/include -I$csubdir");
} else {
    push @opts, ('LIBS' => `$pkg_config --libs linebreak`);
    push @opts, ('INC' => `$pkg_config --cflags linebreak`); 
}

WriteMakefile(
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
	# Un-comment this if you add C files to link with later:
	# 'OBJECT'	=> '$(O_FILES)', # link all the C files too
	@opts,
);
