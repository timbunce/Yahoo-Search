#!/usr/local/bin/perl -w
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME	  => 'Yahoo::Search',
    ABSTRACT_FROM => 'lib/Yahoo/Search.pm',
    VERSION_FROM  => 'lib/Yahoo/Search.pm',
    PREREQ_PM	  => {
                       'LWP::UserAgent' => 0,
                       'HTTP::Request'  => 0,
                       'URI'            => 0,
                      },
    AUTHOR        => 'Jeffrey Friedl <jfriedl@yahoo.com>',
);
