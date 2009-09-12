use Test::More;
use Unicode::GCString;

BEGIN { plan tests => 17 }

($s, $r) = (pack('U*', 0x300, 0, 0x0D, 0x41, 0x300, 0x301, 0x3042, 0xD, 0xA,
		 0xAC00, 0x11A8),
	    pack('U*', 0xAC00, 0x11A8, 0xD, 0xA, 0x3042, 0x41, 0x300, 0x301,
		 0xD, 0, 0x300));
$string = Unicode::GCString->new($s);
is($string->length, 7);
is($string->columns, 5);

is($r, Unicode::GCString->new(join '', reverse map {$_->[0]} @{$string})->as_string);

$string = Unicode::GCString->new(
    pack('U*', 0x1112, 0x1161, 0x11AB, 0x1100, 0x1173, 0x11AF));
is($string->length, 2);
is($string->columns, 4);

is($string, $string->copy);

$s1 = pack('U*', 0x1112, 0x1161);
$s2 = pack('U*', 0x11AB, 0x1100, 0x1173, 0x11AF);
$g1 = Unicode::GCString->new($s1);
$g2 = Unicode::GCString->new($s2);
is($g1.$g2, $string);
is(($g1.$g2)->length, 2);
is(($g1.$g2)->columns, 4);
is($g1.$s2, $string);
is(($g1.$s2)->length, 2);
is(($g1.$s2)->columns, 4);
is($s1.$g2, $string);
is(($s1.$g2)->length, 2);
is(($s1.$g2)->columns, 4);
$s1 .= $g2;
is($s1, $string);
$g1 .= $s2;
is($g1, $string);
