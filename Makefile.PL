use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;
use vars qw(@ISA);
@ISA = qw(ExtUtils::MakeMaker);
require 'lib/Unicode/LineBreak/Version.pm';

sub postamble {
    my $ret = '';
    foreach my $version (@{Unicode::LineBreak::UNICODE_VERSIONS()}) {
	$ret .= $version.'$(OBJ_EXT)'.": c/$version.c c/linebreak.h\n";
	$ret .= "\t".'$(CCCMD) $(CCCDLFLAGS) "-I$(PERL_INC)" $(PASTHRU_DEFINE) $(DEFINE) -o $@ '."c/$version.c\n";
    }
    $ret;
}

my @opts = ();
my $libthai = `pkg-config --modversion libthai`;
chomp $libthai;
if ($libthai and ($ARGV[0] || '') ne 'nolibthai') {
    print "Use libthai $libthai\n";
    push @opts, ('DEFINE' => "-DUSE_LIBTHAI=\\\"libthai/$libthai\\\"",
		 'INC' => '-I./c ' . `pkg-config --cflags libthai`,
		 'LIBS' => `pkg-config --libs libthai`,
		 );
} else {
    push @opts, ('INC' => '-I./c');
}
my $object = '$(BASEEXT)$(OBJ_EXT)';
$object .= ' ';
$object .= Unicode::LineBreak::DEFAULT_UNICODE_VERSION().'$(OBJ_EXT)';
push @opts, ('OBJECT' => $object);

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
	# My external library
	# 'MYEXTLIB'	=> 'mylib/libmylib$(LIB_EXT)',
	@opts,
);

