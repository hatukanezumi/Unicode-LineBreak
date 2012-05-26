use 5.008;
use strict;

package MY;
use ExtUtils::MakeMaker;
use Config;

my $csubdir = 'sombok';
my $sombok_atleast_version = '2.2.0';
my $sombok_max_version = '2.99.99';
my $pkg_config = $ENV{'PKG_CONFIG'} || 'pkg-config';
my $enable_libthai = 1;
my $bundled_sombok = 0;
my $unicode = 6.1.0;
my $copy_unidata = 0;
my $sombok;
my $libthai;

sub clean {
    my $inherited = shift->SUPER::clean(@_);
    $inherited =~ s{(\n*)\z}
	{\n\t\$(RM_F) $csubdir\$(DIRFILESEP)Makefile.PL $csubdir\$(DIRFILESEP)include\$(DIRFILESEP)sombok.h $csubdir\$(DIRFILESEP)lib\$(DIRFILESEP)*\$(OBJ_EXT)$1};
    $inherited;
}

sub test {
    my $inherited = shift->SUPER::test(@_);
    # Get UNIDATA before testing.
    $inherited =~ s/^(test\s*:+\s*)/${1}copy_unidata /m
	if $copy_unidata;
    $inherited;
}

sub distdir {
    my $inherited = shift->SUPER::distdir(@_);
    if ($copy_unidata) {
	open my $mani, '<', 'MANIFEST' or die "$!";
	$inherited =~ s/^(distdir\s*:+\s*)/${1}copy_unidata /m
	    if scalar grep m{test-data/LineBreakTest.txt}, <$mani>;
	close $mani;
    }
    $inherited;
}

sub postamble {
    my $self = shift;

    my $cd_make = $self->cd($csubdir, '$(MAKE) all');

    return <<EOF;
\$(MYEXTLIB): $csubdir\$(DIRFILESEP)Makefile
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

if (open my $fp, '<', "$csubdir/UNICODE") {
    $unicode = <$fp>;
    $unicode =~ s/\s+$//;
    close $fp;
}

foreach my $arg (@ARGV) {
    if ($arg eq '--disable-libthai') {
	$enable_libthai = 0;
    } elsif ($arg eq '--with-bundled-sombok') {
	$bundled_sombok = 1;
    } elsif ($arg =~ /^--with-unicode-version=(\S+)$/) {
	$unicode = $1;
    }
}

my %opts = ('LIBS' => '', 'INC' => '');

$enable_libthai = 0 if system("$pkg_config --exists libthai") >> 8;
if ($enable_libthai) {
    $libthai = `$pkg_config --modversion libthai`;
    chomp $libthai;
    $libthai ||= 'unknown';
    print "Use libthai $libthai\n";
}

if (system("$pkg_config --atleast-version=$sombok_atleast_version sombok")
    >> 8 or
    system("$pkg_config --max-version=$sombok_max_version sombok") >> 8) {
    $bundled_sombok = 1;
}
if ($bundled_sombok) {
    if (open my $fp, '<', "$csubdir/VERSION") {
	$sombok = <$fp>;
	close $fp;
	$sombok =~ s/\s+$//;
	$sombok ||= 'bundled';
    }

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
    if ($enable_libthai) {
	$h =~ s{\"config.h\"}
	       {\"EXTERN.h\"\n#include \"perl.h\"\n#include \"XSUB.h\"\n#define USE_LIBTHAI \"libthai/$libthai\"};
    } else {
	$h =~ s{\"config.h\"}
               {\"EXTERN.h\"\n#include \"perl.h\"\n#include \"XSUB.h\"\n#undef USE_LIBTHAI};
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

    $opts{'MYEXTLIB'} = $myextlib;
    $opts{'INC'} .= " -I$csubdir\$(DIRFILESEP)include";
    $opts{'depend'} = { '$(OBJECT)' => '$(MYEXTLIB)' };
} else {
    $sombok = `$pkg_config --modversion sombok`;
    chomp $sombok;
    print "Use sombok $sombok\n";
    $opts{'LIBS'} .= ' '.`$pkg_config --libs sombok`;
    $opts{'INC'} .= ' '.`$pkg_config --cflags sombok`; 
}

if ($enable_libthai) {
    $opts{'LIBS'} .= ' '.`$pkg_config --libs libthai`;
    $opts{'INC'} .= ' '.`$pkg_config --cflags libthai`;
}

$opts{'LIBS'} =~ s/\s+/ /g;
$opts{'INC'} =~ s/\s+/ /g;

$copy_unidata = (! -e "test-data/LineBreakTest.txt" ||
                 ! -e "test-data/GraphemeBreakTest.txt");

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
	    'ExtUtils::MakeMaker'   => '6.26',
	    'Test::More'	=> '0.45',
	},
	%opts,
	'dist'		=> {
	    'PREOP'		=> "\$(FULLPERL) -i -pe \'s/^(version:\\s+).*/\$\${1}\$(VERSION)/\' META.yml; \$(FULLPERL) -i -pe \'s/^(\\s*\"version\"\\s*:\\s*).*/\$\${1}\"\$(VERSION)\"/\' META.json; \$(FULLPERL) -i -pe \'s/^(%define version\\s+).*/\$\${1}\$(VERSION)/; s/^(%define sombok_version\\s+).*/\$\${1}$sombok_atleast_version/\' perl-Unicode-LineBreak.spec",
	},
);
