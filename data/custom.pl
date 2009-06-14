#-*- perl -*-

if ($ARGV[0] eq 'lb') {
    goto LB_CUSTOM;
} elsif ($ARGV[0] eq 'ea') {
    goto EA_CUSTOM;
}

LB_CUSTOM:

print <<'EOF';
## SA characters may be categorized by their Grapheme_Break properties.
## See [UAX #29].
EOF

open LB, '<', "LineBreak-$ARGV[1].txt";
while (<LB>) {
    chomp $_;
    s/\s*#\s*(.*)$//;
    $name = $1;
    next unless /\S/;
    ($code, $prop) = split /;/;
    if ($prop eq 'SA') {
	$SA{$code} = 'SAbase';
    } elsif ($prop eq 'NS') {
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

open GB, '<', "GraphemeBreakProperty-$ARGV[1].txt";
while (<GB>) {
    chomp $_;
    s/\s*#.+//;
    ($code, $prop) = split /\s*;\s*/;
    ($beg, $end) = split /\.\./, $code;
    $end = $beg unless defined $end;
    foreach my $c ((hex("0x$beg")..hex("0x$end"))) {
	$c = sprintf "%04X", $c;
	if ($SA{$c}) {
	    if ($prop eq 'Extend' or $prop eq 'SpacingMark') {
		$SA{$c} = 'SAextend';
	    } elsif ($prop eq 'Prepend') { 
		$SA{$c} = 'SAprepend';
	    }
	}
    }
}

open SCR, '<', "Scripts-$ARGV[1].txt";
while (<SCR>) {
    chomp $_;
    s/\s*#.+//;
    ($code, $prop) = split /\s*;\s*/;
    ($beg, $end) = split /\.\./, $code;
    $end = $beg unless defined $end;
    foreach my $c ((hex("0x$beg")..hex("0x$end"))) {
	$c = sprintf "%04X", $c;
	$SCR{$c} = $prop;
    }
}

open UD, '<', "UnicodeData-$ARGV[1].txt";
open SASCR, '>', 'SAScripts.txt';
while (<UD>) {
    ($code, $name, $cat) = split /;/;
    if ($SA{$code}) {
	$prop = $SA{$code};
	print "$code;$prop # $name\n";
	print SASCR "$code;$SCR{$code} # $name\n";
    } elsif ($NS{$code}) {
	print "$code;$NS{$code} # $name\n";
    }
}
close SASCR;
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
    }
}
close UD;
exit 0;
