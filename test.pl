#!/usr/local/bin/perl -w
use strict;
## By virtue of being named "test.pl", this program is automatically run
## via "make test".

use Yahoo::Search AppId => "Perl API install test",
                  Count => 1;

my @Results = Yahoo::Search->Results(Doc => 'Larry Wall');
if (@Results == 1 and $Results[0]->Url =~ m{^https?://}) {
    print "Yahoo::Search test passes\n";
}
else {
    die "Yahoo::Search test failed: $@\n";
}
