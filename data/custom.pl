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

open LB, '<', "LineBreak-$ARGV[1].txt";
while (<LB>) {
    chomp $_;
    s/\s*#\s*(.*)$//;
    $name = $1;
    next unless /\S/;
    ($code, $prop) = split /;/;
    if ($prop eq 'NS') {
	$NS{$code} = '@KANA_NONSTARTERS:KANA_SMALL_LETTERS'
	    if $name =~ /LETTER SMALL/;
	$NS{$code} = '@KANA_NONSTARTERS:KANA_PROLONGED_SOUND_MARKS'
	    if $name =~ /PROLONGED SOUND MARK/;
	$NS{$code} = '@KANA_NONSTARTERS:IDEOGRAPHIC_ITERATION_MARKS'
	    if $name =~ /ITERATION MARK/;
	$NS{$code} = '@KANA_NONSTARTERS:MASU_MARK'
	    if $name =~ /MASU MARK/;
    }
}

open UD, '<', "UnicodeData-$ARGV[1].txt";
while (<UD>) {
    ($code, $name, $cat) = split /;/;
    if ($NS{$code}) {
	print "$code;$NS{$code} # $name\n";
    }
}
close UD;

exit 0;

EA_CUSTOM:

open EA, '<', "EastAsianWidth-$ARGV[1].txt";
while (<EA>) {
    chomp $_;
    s/\s*#\s*(.*)$//;
    $name = $1;
    next unless /\S/;
    ($code, $prop) = split /;/;
    if ($prop eq 'A') {
	if ($name =~ /^LATIN (CAPITAL|SMALL) (LETTER|LIGATURE)/) {
	    $A{$code} = '@AMBIGUOUS_ALPHABETICS:AMBIGUOUS_LATIN';
	} elsif ($name =~ /^GREEK (CAPITAL|SMALL) (LETTER|LIGATURE)/) {
	    $A{$code} = '@AMBIGUOUS_ALPHABETICS:AMBIGUOUS_GREEK';
	} elsif ($name =~ /^CYRILLIC (CAPITAL|SMALL) (LETTER|LIGATURE)/) {
	    $A{$code} = '@AMBIGUOUS_ALPHABETICS:AMBIGUOUS_CYRILLIC';
	}
    } elsif ($prop eq 'Na' and 0x7F < hex("0x$code") and
	     $name !~ /^MATHEMATICAL/ and $name !~ /WHITE PARENTHESIS/) {
	$Na{$code} = '@QUESTIONABLE_NARROW_SIGNS';
    }
}
close EA;

open UD, '<', "UnicodeData-$ARGV[1].txt";
while (<UD>) {
    ($code, $name, $cat) = split /;/;
    if ($cat =~ /^(Me|Mn|Cc|Cf|Zl|Zp)$/) {
	print "$code;Z # $name\n";
    } elsif ($A{$code}) {
	print "$code;$A{$code} # $name\n";
    } elsif ($Na{$code}) {
	print "$code;$Na{$code} # $name\n";
    }
}
close UD;
exit 0;
