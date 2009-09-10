use Test::More;
use Unicode::GCString;

BEGIN { plan tests => 5 }

($s, $r) = (pack('U*', 0x300, 0, 0x0D, 0x41, 0x300, 0x301, 0x3042, 0xD, 0xA,
		 0xAC00, 0x11A8),
	    pack('U*', 0xAC00, 0x11A8, 0xD, 0xA, 0x3042, 0x41, 0x300, 0x301,
		 0xD, 0, 0x300));
$string = Unicode::GCString->new($s);
is($string->length, 7);
is($string->columns, 5);

while (my $gc = <$string>) { push @gc, $gc }
is($r, Unicode::GCString->new(join '', reverse map {$_->[0]} @gc)->as_string);

$string = Unicode::GCString->new(
    pack('U*', 0x1112, 0x1161, 0x11AB, 0x1100, 0x1173, 0x11AF));
is($string->length, 2);
is($string->columns, 4);

=begin comment

$s1 = Unicode::GCString->new(
    pack('U*', 0x1112, 0x1161));
$s2 = Unicode::GCString->new(
    pack('U*', 0x11AB, 0x1100, 0x1173, 0x11AF));
diag(Encode::encode_utf8($s1.$s2));
is($s1.$s2, $string);
is(($s1.$s2)->length, 2);
is(($s1.$s2)->columns, 4);
diag(join '', map {"[".join(',',@$_)."]"} @{($s1.$s2)->{str}});

=end comment

=cut
