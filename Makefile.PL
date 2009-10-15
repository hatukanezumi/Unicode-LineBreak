use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;
use vars qw(@ISA);
@ISA = qw(ExtUtils::MakeMaker);
require 'lib/Unicode/LineBreak/Version.pm';

my $enable_libthai;
my $csubdir = 'linebreak';
my $pkg_config = $ENV{'PKG_CONFIG'} || 'pkg-config';

sub clean_subdirs {
    return <<EOF;
clean_subdirs:
\tif \$(TEST_F) $csubdir/Makefile; then cd $csubdir; \$(MAKE) distclean; fi
EOF
}

sub postamble {
    return <<EOF;
\$(MYEXTLIB): $csubdir/Makefile
\tcd $csubdir && \$(MAKE)
$csubdir/Makefile: $csubdir/configure
\tcd $csubdir && \\
\t\$(PERL) -i -ne "print unless /\\bVERSION\\b/" config.h.in && \\
\t./configure --disable-shared --enable-static \\
\t--enable-libthai=$enable_libthai \\
\tCFLAGS='\$(CCFLAGS) \$(OPTIMIZE) \$(CCCDLFLAGS)'
$csubdir/configure: $csubdir/configure.in
\tcd $csubdir && ./autogen.sh
EOF
}

my @opts = ();
my $libthai = `$pkg_config --modversion libthai`;
chomp $libthai;
if ($libthai and ($ARGV[0] || '') ne 'nolibthai') {
    print "Use libthai $libthai\n";
    $enable_libthai = 'yes';
    push @opts, ('LIBS' => `$pkg_config --libs libthai`);
} else {
    $enable_libthai = 'no';
}
push @opts, ('INC' => "-I$csubdir/include -I$csubdir");

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
	'MYEXTLIB' => "$csubdir/.libs/liblinebreak\$(LIB_EXT)",
	# Un-comment this if you add C files to link with later:
	# 'OBJECT'	=> '$(O_FILES)', # link all the C files too
	@opts,
);
