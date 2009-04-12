## 

UNICODE_VERSION = 5.1.0

UNICODEDATA = UnicodeData-$(UNICODE_VERSION).txt
LINEBREAK = LineBreak-$(UNICODE_VERSION).txt
EASTASIANWIDTH = EastAsianWidth-$(UNICODE_VERSION).txt

all: ../lib/Unicode/LineBreak/Data.pm ../lib/Unicode/LineBreak/Rules.pm

../lib/Unicode/LineBreak/Data.pm: $(EASTASIANWIDTH) EastAsianWidth.custom LineBreak.custom data2pl.pl
	( \
	  echo '#-*- perl -*-'; \
	  echo ''; \
	  echo 'package Unicode::LineBreak;'; \
	  echo ''; \
	  perl data2pl.pl $(EASTASIANWIDTH) EastAsianWidth.custom ea; \
	  perl data2pl.pl $(LINEBREAK) LineBreak.custom lb; \
	  echo '1;' \
	) > $@

../lib/Unicode/LineBreak/Rules.pm: Rules rules2pl.pl
	perl rules2pl.pl $< > $@


EastAsianWidth.custom: $(UNICODEDATA)
	( \
	  echo '## Zero-width characters.'; \
	  perl -ne '@_=split(/;/,$$_); print "$$_[0];z # $$_[1]\n" if $$_[2]=~/M.|Cc|Cf|Zl|Zp/' $< \
	) > $@

LineBreak.custom: $(UNICODEDATA) $(LINEBREAK)
	( \
	  echo '## SA characters optionally treated as CM (see UAX #14, 6.1 LB1)'; \
	  echo '## which has general category Mc or Mn.'; \
	  sed -ne 's/^\([^;]*\);SA .*/\1/p' $(LINEBREAK) | \
	  perl -ne 'BEGIN { while (<STDIN>) {chomp $$_; $$SA{$$_}=1} }' \
	  -e '@_=split(/;/); print "$$_[0];SAcm # $$_[1]\n" if $$SA{$$_[0]} and $$_[2]=~/Mc|Mn/' \
	  $(UNICODEDATA); \
	  echo ''; \
	  echo '## NS characters optionally treated as ID (see JIS X 4051, 6.1.1 note 8).'; \
	  sed -ne '/LETTER SMALL/s/;NS /;NSid /p' \
	      -e '/PROLONGED SOUND MARK/s/;NS /;NSid /p' $(LINEBREAK) \
	) > $@

