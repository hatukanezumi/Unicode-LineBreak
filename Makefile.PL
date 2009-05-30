use 5.008;
use ExtUtils::MakeMaker;

my @opts = ('DEFINE' => "-DUSE_LIBTHAI=0");
if ($ARGV[0] eq 'noxs') {
    @opts = ('XS' => {}, 'C' => []);
} elsif (!$ARGV[0] or $ARGV[0] ne 'nolibthai') {
    my $libthai = `pkg-config --modversion libthai`;
    chomp $libthai;
    if ($libthai) {
	print "Use libthai\n";
	@opts = ('DEFINE' => "-DUSE_LIBTHAI=1",
		 'INC' => `pkg-config --cflags libthai`,
		 'LIBS' => `pkg-config --libs libthai`,
		 );
    }
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
	    'Test::More'	=> 0,
	},
	# Un-comment this if you add C files to link with later:
	# 'OBJECT'	=> '$(O_FILES)', # link all the C files too
	# My external library
	# 'MYEXTLIB'	=> 'mylib/libmylib$(LIB_EXT)',
	@opts,
);

