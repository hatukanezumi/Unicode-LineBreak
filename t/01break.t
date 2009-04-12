use strict;
use Test;
use Encode;

BEGIN { plan tests => 9 }

use Unicode::LineBreak;
$Unicode::LineBreak::Config = {
    Detect7bit => 'YES',
    Mapping => 'EXTENDED',
    Replacement => 'DEFAULT',
    Charset => 'UTF-8',
    OutputCharset => 'UTF-8',
    Break => "\n",
    MaxColumns => 76,
};

my @langs = qw(ar el fr ja ja-a ko ru th zh);

foreach my $lang (@langs) {
    open IN, "<testin/$lang.in" or die "open: $!";
    my $instring = join '', <IN>;
    close IN;
    my $lb = Unicode::LineBreak->new($instring);
    $instring = $lb->break;

    #XXXprint STDERR $instring;
    open OUT, "<testin/$lang.out" or die "open: $!";
    my $outstring = join '', <OUT>;
    #XXXmy $outstring = $instring;
    close OUT;

    ok($instring, $outstring);
}    

1;

