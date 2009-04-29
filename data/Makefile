## 

UNICODE_VERSION = 5.1.0

UNICODEDATA = UnicodeData-$(UNICODE_VERSION).txt
LINEBREAK = LineBreak-$(UNICODE_VERSION).txt
EASTASIANWIDTH = EastAsianWidth-$(UNICODE_VERSION).txt

all: ../lib/Unicode/LineBreak/Data.pm ../lib/Unicode/LineBreak/Rules.pm

../lib/Unicode/LineBreak/Data.pm: $(EASTASIANWIDTH) $(LINEBREAK) EastAsianWidth.custom LineBreak.custom data2pl.pl map2pl.pl
	( \
	  echo '#-*- perl -*-'; \
	  echo ''; \
	  echo 'package Unicode::LineBreak;'; \
	  echo ''; \
	  perl data2pl.pl $(LINEBREAK) LineBreak.custom lb; \
	  perl map2pl.pl $(EASTASIANWIDTH) EastAsianWidth.custom ea; \
	  perl map2pl.pl $(LINEBREAK) LineBreak.custom lb; \
	  echo '1;' \
	) > $@

../lib/Unicode/LineBreak/Rules.pm: Rules rules2pl.pl
	perl rules2pl.pl $< > $@

EastAsianWidth.custom: $(UNICODEDATA) $(EASTASIANWIDTH)
	( \
	  echo '## Zero-width characters.'; \
	  perl -ne '@_=split(/;/,$$_); print "$$_[0];z # $$_[1]\n" if $$_[2]=~/M.|Cc|Cf|Zl|Zp/' $(UNICODEDATA); \
	  echo ''; \
	  echo '## Ambiguous width alphabetics.'; \
	  perl -ne '/# LATIN (CAPITAL|SMALL) (LETTER|LIGATURE)/ && s/;A /;AnLat / && print;' \
	  -e '/# GREEK (CAPITAL|SMALL) (LETTER|LIGATURE)/ && s/;A /;AnGre / && print;' \
	  -e '/# CYRILLIC (CAPITAL|SMALL) (LETTER|LIGATURE)/ && s/;A /;AnCyr / && print;' \
	  $(EASTASIANWIDTH); \
	) > $@

LineBreak.custom: $(UNICODEDATA) $(LINEBREAK)
	( \
	  echo '## SA characters optionally treated as CM (see UAX #14, 6.1 LB1)'; \
	  echo '## which has general category Mc or Mn.'; \
	  sed -ne 's/^\([^;]*\);SA .*/\1/p' $(LINEBREAK) | \
	  perl -ne 'BEGIN { while (<STDIN>) {chomp $$_; $$SA{$$_}=1} }' \
	  -e '@_=split(/;/);' \
	  -e 'if ($$SA{$$_[0]}) { if ($$_[2]=~/Mc|Mn/) { print "$$_[0];SAcm # $$_[1]\n" } else { print "$$_[0];SAal # $$_[1]\n" } }' \
	  $(UNICODEDATA); \
	  echo ''; \
	  echo '## NS characters optionally treated as ID (see JIS X 4051, 6.1.1 note 8).'; \
	  sed -ne '/LETTER SMALL/s/;NS /;NSidKana /p' \
	      -e '/PROLONGED SOUND MARK/s/;NS /;NSidLong /p' \
	      -e '/ITERATION MARK/s/;NS /;NSidIter /p' \
	      -e '/MASU MARK/s/;NS /;NSidMasu /p' \
	  $(LINEBREAK) \
	) > $@

