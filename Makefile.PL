use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;
use vars qw(@ISA);
@ISA = qw(ExtUtils::MakeMaker);

my $csubdir = 'linebreak';
my $linebreak_atleast_version = '1.4';
my $pkg_config = $ENV{'PKG_CONFIG'} || 'pkg-config';
my @args = ();

sub clean_subdirs {
    return <<EOF;
clean_subdirs:
\tif \$(TEST_F) $csubdir/Makefile; then cd $csubdir; \$(MAKE) distclean; fi
EOF
}

sub postamble {
    my $args = join ' ', map {s/\'/\\\'/g; "'$_'"; } @args;
    return <<EOF;
\$(MYEXTLIB): $csubdir/Makefile
\tcd $csubdir && \$(MAKE)
$csubdir/Makefile: $csubdir/configure
\tcd $csubdir && chmod u+x configure && \\
\t./configure --disable-shared --enable-static $args \\
\tCFLAGS='\$(CCFLAGS) \$(OPTIMIZE) \$(CCCDLFLAGS)'
$csubdir/configure: $csubdir/configure.ac
\tcd $csubdir && ./autogen.sh
EOF
}

my $enable_libthai = 'yes';
my $bundled_linebreak = 'no';
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
my $libthai = `$pkg_config --modversion libthai`;
chomp $libthai;
if ($libthai and $enable_libthai eq 'yes') {
    print "Use libthai $libthai\n";
    push @args, '--enable-libthai';
    push @opts, ('LIBS' => `$pkg_config --libs libthai`);
} else {
    push @args, '--disable-libthai';
}
if (system("$pkg_config --atleast-version=$linebreak_atleast_version ".
	    "liblinebreak") % 256) {
    $bundled_linebreak = 'yes';
}
if ($bundled_linebreak = 'yes') {
    push @opts, ('MYEXTLIB' => "$csubdir/.libs/liblinebreak\$(LIB_EXT)");
    push @opts, ('INC' => "-I$csubdir/include -I$csubdir");
} else {
    push @opts, ('LIBS' => `$pkg_config --libs liblinebreak`);
    push @opts, ('INC' => `$pkg_config --cflags liblinebreak`); 
}

WriteMakefile(
	'NAME'		=> 'Unicode::LineBreak',
	'ABSTRACT_FROM'	=> 'lib/Unicode/LineBreak.pod',
	'VERSION_FROM'	=> 'lib/Unicode/LineBreak/Version.pm',
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
