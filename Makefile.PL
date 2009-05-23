use 5.008;
use ExtUtils::MakeMaker;

my @noxs;
if (scalar @ARGV and $ARGV[0] eq 'noxs') {
    @noxs = ('XS' => {}, 'C' => []);
} else {
    @noxs = ();
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
	'LIBS'		=> [''], # e.g., '-lm'
	'DEFINE'	=> '', # e.g., '-DHAVE_SOMETHING'
	'INC'		=> '', # e.g., '-I/usr/include/other'
	# Un-comment this if you add C files to link with later:
	# 'OBJECT'	=> '$(O_FILES)', # link all the C files too
	# My external library
	# 'MYEXTLIB'	=> 'mylib/libmylib$(LIB_EXT)',
	@noxs,
);

