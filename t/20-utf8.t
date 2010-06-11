use strict;

use Test::More tests => 4;
use Data::Dumper;
use Encode;
use utf8;

use Yahoo::Search AppId => "Perl API install test",
                  Count => 10;

# utf8 search string
my $utf8_string = "dudenstraße";
ok Encode::is_utf8($utf8_string, 1), 'is_utf8';
my $count = 10;

my @Results = Yahoo::Search->Results(
    Doc => $utf8_string,
    Count => $count,
);
is @Results, $count;

my @Summary = map { $_->Summary } @Results;
is @Summary, $count, 'got summaries';
print Dumper(\@Summary);

#use DBI; warn DBI::neat_list(\@Summary);
my @utf8_matches = grep { Encode::is_utf8($_, 1) } @Summary;
ok @utf8_matches, 'is_utf8 should be true on some';

