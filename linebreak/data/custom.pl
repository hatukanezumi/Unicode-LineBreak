#-*- perl -*-

if ($ARGV[0] eq 'lb') {
    goto LB_CUSTOM;
} elsif ($ARGV[0] eq 'ea') {
    goto EA_CUSTOM;
} else {
    exit 0;
}

LB_CUSTOM:

print <<'EOF';
## SA characters may be categorized by their Grapheme_Cluster_Break properties.
## See [UAX #29].
EOF

exit 0;

EA_CUSTOM:

open UD, '<', "UnicodeData-$ARGV[1].txt";
while (<UD>) {
    ($code, $name, $cat) = split /;/;
    if ($cat =~ /^(Me|Mn|Cc|Cf|Zl|Zp)$/) {
	print "$code;Z # $name\n";
    }
}
close UD;
exit 0;
