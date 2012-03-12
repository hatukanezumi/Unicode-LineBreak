use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;
use Config;

my $csubdir = 'sombok';
my $sombok_atleast_version = '2.1.1';
my $sombok_max_version = '2.99.99';
my $pkg_config = $ENV{'PKG_CONFIG'} || 'pkg-config';
my $enable_libthai = 'yes';
my $bundled_sombok = 'no';
my $libthai;
my $unicode;

sub clean {
    my $inherited = shift->SUPER::clean(@_);
    $inherited =~ s{(\n*)\z}
	{\n\t\$(RM_F) $csubdir/Makefile.PL $csubdir/include/sombok.h $csubdir/lib/*\$(OBJ_EXT)$1};
    $inherited;
}

sub test {
    my $inherited = shift->SUPER::test(@_);
    $inherited =~ s/^(test\s*:+\s*)/${1}copy_unidata /m;
    $inherited;
}

sub distdir {
    my $inherited = shift->SUPER::distdir(@_);
    open my $mani, '<', 'MANIFEST' or die "$!";
    $inherited =~ s/^(distdir\s*:+\s*)/${1}copy_unidata /m
	if scalar grep m{test-data/LineBreakTest.txt}, <$mani>;
    close $mani;
    $inherited;
}

sub postamble {
    my $self = shift;

    my $cd_make = $self->cd($csubdir, '$(MAKE) all');

    return <<EOF;
\$(MYEXTLIB): $csubdir/Makefile
\t$cd_make

copy_unidata :
\tcd test-data; \\
\t[ -f LineBreakTest.txt ] || \\
\twget -q -N -O LineBreakTest.txt \\
\tftp://unicode.org/Public/$unicode/ucd/auxiliary/LineBreakTest*.txt \\
\t|| true
\tcd test-data; \\
\t[ -f GraphemeBreakTest.txt ] || \\
\twget -q -N -O GraphemeBreakTest.txt \\
\tftp://unicode.org/Public/$unicode/ucd/auxiliary/GraphemeBreakTest*.txt \\
\t|| true
EOF
}

$unicode = `cat $csubdir/UNICODE`;
$unicode =~ s/\s+$//;
foreach my $arg (@ARGV) {
    if ($arg eq '--disable-libthai') {
	$enable_libthai = 'no';
    } elsif ($arg eq '--with-bundled-sombok') {
	$bundled_sombok = 'yes';
    } elsif ($arg =~ /^--with-unicode-version=(\S+)$/) {
	$unicode = $1;
    } else {
	die "Unknown option $arg\n";
    }
}
my @opts = ();
$libthai = `$pkg_config --modversion libthai`;
chomp $libthai;
$libthai ||= 'unknown';
if ($libthai ne 'unknown' and $enable_libthai eq 'yes') {
    print "Use libthai $libthai\n";
    push @opts, ('LIBS' => `$pkg_config --libs libthai`);
}
if (system("$pkg_config --atleast-version=$sombok_atleast_version sombok")
    >> 8 or
    system("$pkg_config --max-version=$sombok_max_version sombok") >> 8) {
    $bundled_sombok = 'yes';
}
if ($bundled_sombok eq 'yes') {
    my $sombok = `cat $csubdir/VERSION`;
    $sombok =~ s/\s+$//;
    $sombok ||= 'bundled';

    print "Use bundled sombok $sombok with Unicode $unicode\n";

    # create sombok/Makefile.PL
    unlink "$csubdir/Makefile" if -e "$csubdir/Makefile";
    open my $fp, '<', 'Makefile.PL.sombok' or die $!;
    my $h = join '', <$fp>;
    close $fp;
    $h =~ s/\@UNICODE_VERSION\@/$unicode/g;
    open my $ofp, '>', "$csubdir/Makefile.PL" or die $!;
    print $ofp $h;
    close $ofp;

    # create sombok/include/sombok.h
    open my $fp, '<', "$csubdir/include/sombok.h.in" or die $!;
    my $h = join '', <$fp>;
    close $fp;

    $h =~ s/#ifdef HAVE_CONFIG_H/#if 1/;
    if ($libthai ne 'unknown' and $enable_libthai eq 'yes') {
	$h =~ s{\"config.h\"}
	       {\"EXTERN.h\"\n#    include \"perl.h\"\n#    define USE_LIBTHAI \"libthai/$libthai\"};
    } else {
	$h =~ s{\"config.h\"}
               {\"EXTERN.h\"\n#    include \"perl.h\"\n#    undef USE_LIBTHAI};
    }
    $h =~ s/\@SOMBOK_UNICHAR_T\@/U32/;
    $h =~ s/\@PACKAGE_VERSION\@/$sombok/;
    $h =~ s/\@SOMBOK_UNICHAR_T_IS_WCHAR_T\@//;
    $h =~ s/\@SOMBOK_UNICHAR_T_IS_UNSIGNED_INT\@//;
    $h =~ s/\@SOMBOK_UNICHAR_T_IS_UNSIGNED_LONG\@//;

    open my $ofp, '>', "$csubdir/include/sombok.h" or die $!;
    print $ofp $h;
    close $ofp;

    #XXXmy $define = ($^O eq 'MSWin32') ? '-DMSDOS' : '';
    my $myextlib;
    if ($^O eq 'MSWin32') {
	$myextlib = 'sombok\\libsombok$(LIB_EXT)';
    } elsif ($^O eq 'darwin' && $Config{'ldflags'} =~/-arch ppc64/) {
	$myextlib = '-all_load sombok/libsombok$(LIB_EXT)';
    } else {
	$myextlib = 'sombok/libsombok$(LIB_EXT)';
    }

    push @opts, ('MYEXTLIB' => $myextlib);
    push @opts, ('INC' => "-I$csubdir/include");
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
	    'PREOP'		=> "\$(FULLPERL) -i -pe \'s/^(version:\\s+).*/\$\${1}\$(VERSION)/\' META.yml; \$(FULLPERL) -i -pe \'s/^(%define version\\s+).*/\$\${1}\$(VERSION)/; s/^(%define sombok_version\\s+).*/\$\${1}$sombok_atleast_version/\' perl-Unicode-LineBreak.spec",
	},
);
