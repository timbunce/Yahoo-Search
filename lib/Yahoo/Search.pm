package Yahoo::Search;
use strict;
use Carp;
use Yahoo::Search::Request;

##
## This is the interface to Yahoo!'s web search API.
## Written by Jeffrey Friedl <jfriedl@yahoo.com>
## Copyright (C) 2005 Yahoo! Inc.
##

our $VERSION = '1.0.2'; # last num increases monotonically across all versions

##
## CLASS OVERVIEW
##
##      The main class
##        Yahoo::Search
##      begets
##        Yahoo::Search::Request
##      which begets
##        Yahoo::Search::Response
##      which begets a bunch of
##        Yahoo::Search::Result
##      which beget urls, summaries, etc.
##
## There are plenty of "convenience functions" which appear to bypass some
## of these steps as far as the user's view is concerned.
##

##
## Configuration details for each search space (Doc, Images, Video, ## etc.)...
##
my %Config =
(
  ######################################################################
  # Normal web search
  #
  Doc =>
  {
   Url => 'http://api.search.yahoo.com/WebSearchService/V1/webSearch',

   MaxCount => 50,

   ## The 'Defaults' keys indicate the universe of allowable arguments,
   ## while the values are the defaults for those arguments.
   Defaults => {
                Mode         => undef,
                Count        => 10,
                Start        => 0,
                Type         => 'all',
                AllowAdult   => 0,
                AllowSimilar => 0,
                Language     => undef,
               },

   AllowedMode => {
                   all    => 1,
                   any    => 1,
                   phrase => 1,
                  },
   AllowedType => {
                     all    => 1,

                     html   => 1,
                     msword => 1,
                     pdf    => 1,
                     ppt    => 1,
                     rss    => 1,
                     txt    => 1,
                     xls    => 1,
                    },
  },


  ######################################################################
  # Image search
  #
  Image =>
  {
   Url => 'http://api.search.yahoo.com/ImageSearchService/V1/imageSearch',
   MaxCount => 50,

   Defaults => {
                Mode       => undef,
                Count      => 10,
                Start      => 0,
                Type       => 'all',
                AllowAdult => 0,
               },

   AllowedMode => {
                   all    => 1,
                   any    => 1,
                   phrase => 1,
                  },

   AllowedType => {
                     all  => 1,

                     bmp  => 1,
                     gif  => 1,
                     jpeg => 1,
                     png  => 1,
                    },
  },

  ######################################################################
  # Video file search
  #
  Video =>
  {
   Url => 'http://api.search.yahoo.com/VideoSearchService/V1/videoSearch',

   MaxCount => 50,

   Defaults => {
                Mode       => undef,
                Count      => 10,
                Start      => 0,
                Type       => 'all',
                AllowAdult => 0,
               },

   AllowedMode => {
                   all    => 1,
                   any    => 1,
                   phrase => 1,
                  },

   AllowedType => {
                     all       => 1,

                     avi       => 1,
                     flash     => 1,
                     mpeg      => 1,
                     msmedia   => 1,
                     quicktime => 1,
                     realmedia => 1,
                    },
  },


  ######################################################################
  # "Y! Local" (like Yellow Pages) search
  #
  Local =>
  {
   Url => 'http://api.local.yahoo.com/LocalSearchService/V1/localSearch',

   MaxCount => 20,

   Defaults => {
                Count      => 10,
                Start      => 0,
                Mode       => undef,
                Radius     => undef,
                Street     => undef,
                City       => undef,
                State      => undef,
                PostalCode => undef,
                Location   => undef,
               },
  },


  ######################################################################
  # News search
  #
  News =>
  {
   Url => 'http://api.search.yahoo.com/NewsSearchService/V1/newsSearch',

   MaxCount => 50,

   Defaults => {
                Mode     => undef,
                Count    => 10,
                Start    => 0,
                Sort     => undef,
                Language => undef,
               },

   AllowedMode => {
                   all    => 1,
                   any    => 1,
                   phrase => 1,
                  },

   AllowedSort => {
                   rank   => 1,
                   date   => 1,
                  },
  },

  Spell =>
  {
   Url => 'http://api.search.yahoo.com/WebSearchService/V1/spellingSuggestion',
  },

  Related =>
  {
   Url => 'http://api.search.yahoo.com/WebSearchService/V1/relatedSuggestion',
  },
);

##
## These args are allowed for any Query()
##
my @ExtraQueryArgs = qw[AutoContinue Debug AppId];

##
## Global defaults -- this list may be modified via import()
## and Default();
##
my %GlobalDefault =
(
 ##
 ## Debug is a string with any of: url   (show the url as fetched)
 ##                                xml   (show the resulting xml)
 ##                                hash  (show the resulting hash)
 ##                                stdout (show to stdout instead of stderr)
 ## e.g. "url hash stdout"
 Debug => "",

 ##
 ## if AutoCarp is true (as it is by default), carp on programming errors
 ## (but not 404s, etc.)
 ##
 AutoCarp => 1,

 AutoContinue => 0,

 PreRequestCallback => undef,
);

##
## Helper function to set $@ and, if needed, carp.
##
sub _carp_on_error($)
{
    $@ = shift;
    if ($GlobalDefault{AutoCarp}) {
        carp $@;
    }

    return ();
}


##
## The following private subs are used to validate arguments. They are
## generally called with two args: the search space (Doc, Image, etc.), and
## the text to validate.
##
## If called without the "text to validate" arg, they return a description
## of what args are allowed (tailored to the search space, if appropriate).
##
## Otherwise, they return ($valid, $value).
##
my $allow_positive_integer = sub
{
    my $space = shift; # unused
    if (not @_) {
        return "positive integer";
    }
    my $val = shift;

    if (not $val =~ m/^\d+$/) {
        return (0); # invalid: not a number
    } elsif ($val == 0) {
        return (0); # invalid: not positive
    } else {
        return (1, $val);
    }
};

my $allow_nonnegative_integer = sub
{
    my $space = shift; # unused
    if (not @_) {
        return "non-negative integer";
    }
    my $val = shift;

    if (not $val =~ m/^\d+$/) {
        return (0); # invalid: not a number
    } else {
        return (1, $val);
    }
};

my $allow_positive_float = sub
{
    my $space = shift; # unused
    if (not @_) {
        return "positive number";
    }
    my $val = shift;

    if (not $val =~ m/^(?:  \d+(?: \.\d* )?$ | \.\d+$ )/x) {
        return (0); # invalid: not a number
    } elsif ($val == 0) {
        return (0); # invalid: not positive
    } else {
        return (1, $val);
    }
};

## This has different args than the others -- has $hashref prepended
my $allow_from_hash = sub
{
    my $hashref = shift; #hash in which to check
    my $space   = shift; #unused

    if (not @_) {
        return join '|', sort keys %$hashref;
    }
    my $val = shift;

    if (not $hashref) {
        return (1, $val); # can't tell, so say it's valid
    } elsif ($hashref->{$val}) {
        return (1, $val); # is specifically valid
    } else {
        return (0); # not valid
    }
};

my $allow_boolean = sub
{
    my $space = shift; #unused
    if (not @_) {
        return "true or false";
    }
    my $val = shift;
    return (1, $val ? 1 : 0);
};

my $allow_any = sub
{
    my $space = shift; #unused
    if (not @_) {
        return "any value";
    }
    my $val = shift;
    return (1, $val);
};

my $allow_postal_code = sub
{
    my $space = shift; #unused
    ## only U.S. Zone Improvement Program codes allowed
    if (not @_) {
        return "a US ZIP code"
    }

    my $val = shift;
    if ($val =~ m/^\d\d\d\d\d(?:-?\d\d\d\d)?$/) {
        return (1, $val);
    } else {
        return (0);
    }
};

my $allow_coderef = sub
{
    my $space = shift; #unused
    my $val = shift;
    if (ref($val) eq 'CODE') {
        return (1, $val);
    } else {
        return (0);
    }
};

my $allow_appid = sub
{
    my $space = shift; #unused

    if (not @_) {
        return "something which matches /^[- A-Za-z0-9_()[\\]*+=,.:\@\\\\]{8,40}\$/";
    }

    my $val = shift;
    if ($val =~ m/^[- A-Za-z0-9_()\[\]*+=,.:\@\\]{8,40}$/) {
        return (1, $val);
    } else {
        return (0);
    }
};

our %KnownLanguage =
(
  default => 'any/all languages',

  ar  =>  'Arabic',
  bg  =>  'Bulgarian',
  ca  =>  'Catalan',
  szh =>  'Chinese (simplified)',
  tzh =>  'Chinese (traditional)',
  hr  =>  'Croatian',
  cs  =>  'Czech',
  da  =>  'Danish',
  nl  =>  'Dutch',
  en  =>  'English',
  et  =>  'Estonian',
  fi  =>  'Finnish',
  fr  =>  'French',
  de  =>  'German',
  el  =>  'Greek',
  he  =>  'Hebrew',
  hu  =>  'Hungarian',
  is  =>  'Icelandic',
# id  =>  'Indonesian',
  it  =>  'Italian',
  ja  =>  'Japanese',
  ko  =>  'Korean',
  lv  =>  'Latvian',
  lt  =>  'Lithuanian',
  no  =>  'Norwegian',
  fa  =>  'Persian',
  pl  =>  'Polish',
  pt  =>  'Portuguese',
  ro  =>  'Romanian',
  ru  =>  'Russian',
# sr  =>  'Serbian',
  sk  =>  'Slovak',
  sl  =>  'Slovenian',
  es  =>  'Spanish',
  sv  =>  'Swedish',
  th  =>  'Thai',
  tr  =>  'Turkish',
);

##
## Mapping from arg name to value validation routine.
##
my %ValidateRoutine =
(
 Count        => $allow_positive_integer,
 Start        => $allow_nonnegative_integer,

 Radius       => $allow_positive_float,

 AllowAdult   => $allow_boolean,
 AllowSimilar => $allow_boolean,

 Street       => $allow_any,
 City         => $allow_any,
 State        => $allow_any,
 Location     => $allow_any,

 PostalCode   => $allow_postal_code,

 Mode     => sub { $allow_from_hash->($Config{$_[0]}->{AllowedMode}, @_) },
 Sort     => sub { $allow_from_hash->($Config{$_[0]}->{AllowedSort}, @_) },
 Type     => sub { $allow_from_hash->($Config{$_[0]}->{AllowedType}, @_) },
 Language => sub { $allow_from_hash->(\%KnownLanguage, @_) },

 Debug        => $allow_any,
 AutoContinue => $allow_boolean,
 AutoCarp     => $allow_boolean,

 AppId        => $allow_appid,

 PreRequestCallback => $allow_coderef,
);

##
## returns ($newvalue, $error);
##
sub _validate($$$;$)
{
    my $global   = shift; # true if for a global setting
    my $space    = shift; # Doc, Image, etc.
    my $key      = shift; # "Count", "State", etc.
    my $have_val = @_ ? 1 : 0;
    my $val      = shift;

    if (not $ValidateRoutine{$key}) {
        return (undef, "unknown argument '$key'");
    }

    if (not $global and $key eq 'AutoCarp') {
        return (undef, "AutoCarp is a global setting which can not be used in this context");
    }

    if (not $have_val) {
        return (1);
    }

    my ($valid, $newval) = $ValidateRoutine{$key}->($space, $val);

    if ($valid) {
        return ($newval, undef);
    }

    my $expected = $ValidateRoutine{$key}->($space);
    if ($space) {
        return (undef, "invalid value \"$val\" for $space\'s \"$key\" argument, expected: $expected");
    } else {
        return (undef, "invalid value \"$val\" for \"$key\" argument, expected: $expected");
    }
}


##
## 'import' accepts key/value pairs:
##
sub import
{
    my $class = shift;

    if (@_ % 2 != 0) {
        Carp::confess("bad number of args to 'use $class'");
    }
    my %Args = @_;

    while (my ($key, $val) = each %Args)
    {
        my ($newval, $error) = _validate(1, undef, $key, $val);
        if ($error) {
            Carp::confess("$error, in 'use $class'");
        } else {
            $GlobalDefault{$key} = $newval;
        }
    }
}


##
## Get (or set) one of the default global values. They can be set this way
## (either as Yahoo::Search->Default or $SearchEngine->Default), or via
## Yahoo::Search->new(), or on the 'use' line.
##
## When used with a $SearchEngine object, the value returned is the value
## in effect, which is the global one if the $SearchEngine does not have
## one itself.
##
sub Default
{
    my $class_or_obj = shift; # Yahoo::Search->Default or $SearchEngine->Default
    my $key          = shift;
    my $have_val     = @_ ? 1 : 0;
    my $val          = shift;

    my $global = not ref $class_or_obj;

    my $old;
    if ($global or not exists $class_or_obj->{$key}) {
        $old = $GlobalDefault{$key};
    } else {
        $old = $class_or_obj->{$key};
    }

    if ($have_val)
    {
        my ($newval, $error) = _validate($global, undef, $key, $val);
        if ($error) {
            return _carp_on_error($error);
        }

        if (ref $class_or_obj) {
            $class_or_obj->{$key} = $newval;
        } else {
            $GlobalDefault{$key} = $newval;
        }
    }
    else
    {
        my ($okay, $error) = _validate($global, undef, $key);
        if ($error) {
            return _carp_on_error($error);
        }
    }

    return $old;
}



##
## Maps Yahoo::Search->Query arguments to Y! API parameters.
##
my %ArgToParam =
(
 Mode         => 'type',
 Count        => 'results',
 Start        => 'start',
 Type         => 'format',
 AllowAdult   => 'adult_ok',
 AllowSimilar => 'similar_ok',
 Language     => 'language',
 Sort         => 'sort',
 Radius       => 'radius',
 Street       => 'street',
 City         => 'city',
 State        => 'state',
 PostalCode   => 'zip',
 Location     => 'location',
 AppId        => 'appid',
);


##
## The search-engine constructor.
##
## No args are needed, but any of %ValidateRoutine keys except AutoCarp are
## allowed (they'll be used as the defaults when queries are later
## constructed via this object).
##
sub new
{
    my $class = shift;

    if (@_ % 2 != 0) {
        return _carp_on_error("wrong arg count to $class->new");
    }

    my $SearchEngine = { @_ };

    for my $key (keys %$SearchEngine)
    {
        my ($newval, $error)  = _validate(0, undef, $key, $SearchEngine->{$key});
        if ($error) {
            return _carp_on_error("$error, in call to $class->new");
        }
        $SearchEngine->{$key} = $newval;
    }

    return bless $SearchEngine, $class;
}

##
## Request method (can also be called like a constructor).
## Specs to a specific query are provided, and a Request object is returned.
##
sub Request
{
    my $SearchEngine = shift; # self
    my $SearchSpace  = shift; # "Doc", "Image", "News", etc..
    my $QueryText    = shift; # "Briteny", "egregious compensation semel", etc.

    if (@_ % 2 != 0) {
        return _carp_on_error("wrong arg count");
    }

    my %Args = @_;

    if (not defined $SearchSpace or not $Config{$SearchSpace}) {
        my $list = join '|', sort keys %Config;
        return _carp_on_error("bad search-space identifier, expecting one of: $list");
    }

    if (not defined($QueryText) or length($QueryText) == 0) {
        return _carp_on_error("missing query");
    }

    ##
    ## %Param holds the key/vals we'll send in the request to Yahoo!
    ##
    my %Param = ( query => $QueryText );

    ##
    ## This can be called as a constructor -- if so, $SearchEngine will be
    ## the class name, and we'll want to turn into an object.
    ##
    if (not ref $SearchEngine) {
        $SearchEngine = $SearchEngine->new();
    }

    my %OtherRequestArgs;

    ##
    ## Go through most allowed args, taking the value from this call's arg
    ## list if provided, from the defaults that were registered with the
    ## SearchEngine, or failing those, the defaults for this type of query.
    ##
    for my $key (keys %{ $Config{$SearchSpace}->{Defaults} }, @ExtraQueryArgs)
    {
        ##
        ## Isolate the value we'll use for this request: from our args,
        ## from the defaults registered with the search-engine, or from
        ## the search-space defaults.
        ##
        my $val;
        if (exists $Args{$key}) {
            $val = delete $Args{$key};
        } elsif (exists $SearchEngine->{$key}) {
            $val = $SearchEngine->{$key};
        } elsif (exists $GlobalDefault{$key}) {
            $val = $GlobalDefault{$key};
        } elsif (exists $Config{$SearchSpace}->{Defaults}->{$key}) {
            $val = $Config{$SearchSpace}->{Defaults}->{$key};
        } else {
            $val = undef;
        }

        if (defined $val)
        {
            my ($newval, $error) = _validate(0, $SearchSpace, $key, $val);

            if ($error) {
                return _carp_on_error($error);
            }

            if (my $param = $ArgToParam{$key}) {
                $Param{$param} = $newval;
            } else {
                $OtherRequestArgs{$key} = $newval;
            }
        }
    }

    ##
    ## Any leftover args are bad
    ##
    if (%Args) {
        my $list = join(', ', keys %Args);
        return _carp_on_error("unknown args for '$SearchSpace' query: $list");
    }

    ##
    ## An AppId is required for all calls
    ##
    if (not $Param{'appid'})
    {
        return _carp_on_error("an AppId is required -- please make one up");
    }

    ##
    ## Do some special per-arg-type processing
    ##

    ## ensure that the Count, if given, is not over max
    if (defined $Param{count} and $Param{count} > $Config{$SearchSpace}->{MaxCount}) {
        return _carp_on_error("maximum allowed Count for a $SearchSpace search is $Config{$SearchSpace}->{MaxCount}");
    }

    ## In Perl universe, Start is 0-based, but the Y! API's "start" is 1-based.
    $Param{start}++;

    # 'Local' has special required parameters
    if ($SearchSpace eq 'Local')
    {
        if (not $Param{location}
            and
            not $Param{'zip'}
            and
            not $Param{'state'}
            and
            not $Param{'city'})
        {
            ##
            ## The diff between $Param{} references in the if() above, and
            ## the arg names in the error below, is the %ArgToParam mapping
            ##
            return _carp_on_error("a 'Local' query must have Location, PostalCode, or City+State");
        }
    }

    ##
    ## Okay, we have everything we need to make a specific request object.
    ## Make it and return.
    ##
    return Yahoo::Search::Request->new(
                                       SearchEngine => $SearchEngine,
                                       Space  => $SearchSpace,
                                       Action => $Config{$SearchSpace}->{Url},
                                       Params => \%Param,
                                       %OtherRequestArgs,
                                      );
}

##
## A way to bypass an explicit Request object, jumping from a SearchEngine
## (or nothing) directly to a Response object.
##
sub Query
{
    my $SearchEngine = shift;
    ##
    ## Can be called as a constructor -- if so, $SearchEngine will be the
    ## class name
    ##
    if (not ref $SearchEngine) {
        $SearchEngine = $SearchEngine->new();
    }

    if (my $Request = $SearchEngine->Request(@_)) {
        return $Request->Fetch();
    } else {
        # $@ already set
        return ();
    }
}


##
## A way to bypass explicit Request and Response objects, jumping from a
## SearchEngine (or nothing) directly to a list of Result objects.
##
sub Results
{
    my $Response = Query(@_);

    if (not $Response) {
        # $@ already set
        return ();
    }
    return $Response->Results;
}

##
## A way to bypass explicit Request and Response objects, jumping from a
## SearchEngine (or nothing) directly to a list of links.
##
sub Links
{
    return map { $_->Link } Results(@_);
}


##
## A way to bypass explicit Request and Response objects, jumping from a
## SearchEngine (or nothing) directly to a bunch of html results.
##
sub HtmlResults
{
    return map { $_->as_html } Results(@_);
}

##
## A way to bypass explicit Request and Response objects, jumping from a
## SearchEngine (or nothing) directly to a list of terms
## (For Spell and Related searches)
##
sub Terms
{
    return map { $_->Term } Results(@_);
}


sub MaxCount
{
    if (@_) {
        ##
        ## We'll use only the last arg -- it can be called as either
        ## Yahoo::Search::MaxCount($SearchSpace) or
        ## Yahoo:Search->MaxCount($SearchSpace) and we don't care which.
        ## In either case, the final arg is the search space.
        ##
        my $SearchSpace = $_[-1];
        if ($Config{$SearchSpace} and $Config{$SearchSpace}->{MaxCount}) {
            return $Config{$SearchSpace}->{MaxCount};
        }
    }
    return (); # bad/missing arg
}



1;
__END__

=head1 NAME

Yahoo::Search - Perl interface to Yahoo! Search's public API.

The following search spaces are supported:

=over 3

=item Doc

Common web search for documents (html, pdf, doc, ...)

=item Image

Image search (jpeg, png, gif, ...)

=item Video

Video file search (avi, mpeg, realmedia, ...)

=item News

News article search

=item Local

Yahoo! Local area (ZIP-code-based Yellow-Page like search)

=item Spell

A pseudo-search to fetch a "did you mean?" spelling suggestion for a search term.

=item Related

A pseudo-search to fetch "also try" related-searches for a search term.

=back

(Note: what this Perl API calls "Doc" Search is what Yahoo! calls "Web"
Search. But gee, aren't all web searches "Web" search, including
Image/News/Video/etc?)

Yahoo!'s raw API, which this package uses, is described at:

  http://developer.yahoo.net/

=head1 DOCS

The full documentation for this suite of classes is spread among these packages:

   Yahoo::Search
   Yahoo::Search::Request
   Yahoo::Search::Response
   Yahoo::Search::Result

However, you need C<use> only B<Yahoo::Search>, which brings in the others as needed.

=head1 SYNOPSIS

Yahoo::Search provides a rich and full-featured set of classes for
accessing the various features of Yahoo! Search, and also offers a variety
of has shortcuts to allow simple access, such as the following I<Doc>
search:

 use Yahoo::Search;
 my @Results = Yahoo::Search->Results(Doc => "Britney latest marriage",
                                      AppId => "YahooDemo",
                                      # The following args are optional.
                                      # (Values shown are package defaults).
                                      Mode         => 'all',
                                      Count        => 10,
                                      Start        => 0,
                                      Type         => 'all',
                                      AllowAdult   => 0,
                                      AllowSimilar => 0,
                                      Language     => undef,
                                     );
 warn $@ if $@; # report any errors

 for my $Result (@Results)
 {
     printf "Result: #%d\n",  $Result->I + 1,
     printf "Url:%s\n",       $Result->Url;
     printf "%s\n",           $Result->ClickUrl;
     printf "Summary: %s\n",  $Result->Summary;
     printf "Title: %s\n",    $Result->Title;
     printf "In Cache: %s\n", $Result->CacheUrl;
     print "\n";
 }

The first argument to C<Results> indicates which search space is to be
queried (in this case, I<Doc>). The second argument is the search term or
phrase (described in detail in the next section). Subsequent arguments are
optional key/value pairs (described in detail in the section after that) --
the ones shown in the example are those allowed for a I<Doc> query, with
the values shown being the defaults.

C<Results> returns a list of Yahoo::Search::Result objects, one per item
(in the case of a I<Doc> search, an item is a web page, I<pdf> document,
I<doc> document, etc.). The methods available to a C<Result> object are
dependent upon the search space of the original query -- see
Yahoo::Search::Result documentation for the complete list.

=head1 Search term / phrase

Within a search phrase ("C<Britney latest marriage>" in the example
above), words that you wish to be included even if they would otherwise be
eliminated as "too common" should be proceeded with a "C<+>". Words that you
wish to exclude should be proceeded with a "C<->". Words can be separated
with "C<OR>" (the default for the C<any> Mode, described below), and can be
wrapped in double quotes to identify an exact phrase (the default with the
C<phrase> Mode, also described below).

There are also a number of "Search Meta Words", as described at
http://help.yahoo.com/help/us/ysearch/basics/basics-04.html and
http://help.yahoo.com/help/us/ysearch/tips/tips-03.html , which can stand
along or be combined with C<Doc> searches (and, to some extent, some of the
others -- YMMV):

=over 4

=item B<site:>

allows one to find all documents within a particular domain and all its
subdomains. Example: B<site:yahoo.com>

=item B<hostname:>

allows one to find all documents from a particular host only.
Example: B<hostname:autos.yahoo.comm>

=item B<link:>

allows one to find documents that link to a particular url.
Example: B<link:http://autos.yahoo.com/>

=item B<url:>

allows one to find a specific document in Yahoo!'s index.
Example: B<url:http://edit.autos.yahoo.com/repair/tree/0.html>

=item B<inurl:>

allows one to find a specific keyword as part of indexed urls.
Example: B<inurl:bulgarian>

=item B<intitle:>

allows one to find a specific keyword as part of the indexed titles.
Example: B<intitle:Bulgarian>

=back

As an example combining a number of different search styles, consider

    my @Results = Yahoo::Search->Results(Doc => 'site:TheSmokingGun.com "Michael Jackson" -arrest',
                                         AppId => "YahooDemo");

This returns data about pages at TheSmokingGun.com about Michael Jackson
that don't contain the word "arrest" (yes, there are actually a few such
pages).

=head1 Query arguments

As mentioned above, the arguments allowed in a C<Query> call depend upon
the search space of the query. Here is a table of the possible arguments,
showing which apply to queries of which search space:

                  Doc   Image  Video  News   Local  Spell  Related
                 -----  -----  -----  -----  -----  -----  -------
  AppId           [X]    [X]    [X]    [X]    [X]    [X]     [X]
  Mode            [X]    [X]    [X]    [X]    [X]     .       .
  Start           [X]    [X]    [X]    [X]    [X]     .       .
  Count           [X]    [X]    [X]    [X]    [X]     .       .

  AllowSimilar    [X]     .      .      .      .      .       .
  AllowAdult      [X]    [X]    [X]     .      .      .       .
  Type            [X]    [X]    [X]     .      .      .       .
  Sort             .      .      .     [X]     .      .       .
  Language        [X]     .      .     [X]     .      .       .

  Street           .      .      .      .     [X]     .       .
  City             .      .      .      .     [X]     .       .
  State            .      .      .      .     [X]     .       .
  PostalCode       .      .      .      .     [X]     .       .
  Location         .      .      .      .     [X]     .       .
  Radius           .      .      .      .     [X]     .       .

  AutoContinue    [X]    [X]    [X]    [X]    [X]    [X]     [X]
  Debug           [X]    [X]    [X]    [X]    [X]    [X]     [X]
  PreRequestCallback [X] [X]    [X]    [X]    [X]    [X]     [X]

Here are details of each:

=over 4

=item AppId

A 8-40 character string which identifies the application making use of the
Yahoo! Search API. (Think of it along the lines of an HTTP User-Agent
string.)

The characters allowed are space, plus C<A-Za-z0-9_()[]*+-=,.:@\>

This argument is required of all searches (sorry). You can make up whatever
AppId you'd like, but you are encouraged to register it via the link on

  http://developer.yahoo.net/

especially if you are creating something that will be widly distributed.

As mentioned below in I<Defaults and Default Overrides>, it's particularly
convenient to get the C<AppId> out of the way by putting it on the C<use>
line, e.g.

   use Yahoo::Search AppId => 'just testing';

It then applies to all queries unless explicitly overridden.

=item Mode

Must be one of: C<all> (the default), C<any>, or C<phrase>. Indicates how
multiple words in the search term are used: search for documents with
I<all> words, documents with I<any> words, or documents that contain the
search term as an exact I<phrase>.

=item Start

Indicates the ordinal of the first result to be returned, e.g. the "30" of
"showing results 30-40" (except that C<Start> is zero-based, not
one-based). The default is zero, meaning that the primary results will be
returned.

=item Count

Indicates how many items should be returned. The default is 10. The maximum
allowed depends on the search space being queried: B<20> for C<Local>
searches, and B<50> for others which support the C<Count> argument.

Note that

  Yahoo::Search::MaxCount($SearchSpace)

and

  $SearchEngine->MasCount($SearchSpace)

return the maximum count allowed for the given C<$SearchSpace>.

=item AllowSimilar

If this boolean is true (the default is false), similar results which would
otherwise not be returned are included in the result set.

=item AllowAdult

If this boolean is false (the default), results considered to be "adult"
(i.e. porn) are not included in the result set. Set to true to allow
unfiltered results.

Standard precautions apply about how the "is adult?" determination is not
perfect.

=item Type

This argument can be used to restrict the results to only a specific file
type. The default value, C<all>, allows any type (associated with the
search space) to be returned. Otherwise, the values allowed depend on the
search space:

 Search space    Allowed Type values
 ============    ========================================================
 Doc             all  html msword pdf ppt rss txt xls
 Img             all  bmp gif jpeg png
 Video           all  avi flash mpeg msmedia quicktime realmedia
 News            N/A
 Local           N/A
 Spell           N/A
 Related         N/A

=item Sort

For I<News> searches, the sort may be C<rank> (the default) or
C<date>.

=item Language

If provided, restricts the results to documents in the given language. The
value is an language code such as C<en> (English), C<ja> (Japanese), etc
(mostly ISO 639-1 codes). These are the codes supported:

 code  language
 ----  ---------
  sq   Albanian
  ar   Arabic
  bg   Bulgarian
  ca   Catalan
  szh  Chinese (simplified)
  tzh  Chinese (traditional)
  hr   Croatian
  cs   Czech
  da   Danish
  nl   Dutch
  en   English
  et   Estonian
  fi   Finnish
  fr   French
  de   German
  el   Greek
  he   Hebrew
  hu   Hungarian
  is   Icelandic
  it   Italian
  ja   Japanese
  ko   Korean
  lv   Latvian
  lt   Lithuanian
  no   Norwegian
  fa   Persian
  pl   Polish
  pt   Portuguese
  ro   Romanian
  ru   Russian
  sk   Slovak
  sl   Slovenian
  es   Spanish
  sv   Swedish
  th   Thai
  tr   Turkish

In addition, the code "default" is the same as the lack of a language
specifier, and seems to mean a mix of major world languages, skewed toward
English.

=item Street

=item City

=item State

=item PostalCode

=item Location

These items are for a I<Local> query, and specify the epicenter of the
search. The epicenter must be provided in one of a variety of ways: via the
free-text C<Location>, via C<Street> + C<PostalCode>, via C<Street> +
C<City> + C<State>, via C<PostalCode> alone, or via C<City> + C<State>
alone.

C<Street> is the street address, e.e. "701 First Ave". C<PostalCode> is a
US 5-digit or 9-digit ZIP code (e.g. "94089" or "94089-1234").

If C<Location> is provided, it supersedes the others. It should be a string
along the lines of "701 First Ave, Sunnyvale CA, 94089". The following forms
are recognized:

  city state
  city state zip
  zip
  street, city state
  street, city state zip
  street, zip

Searches that include a street address (either in the C<Location>, or if
C<Location> is empty, in C<Street>) provide for a more detailed epicenter
specification.

=item Radius

For I<Local> searches, indicates how wide an area around the epicenter to
search. The value is the radius of the search area, in miles. The default
radius depends on the search location (urban areas tend to have a smaller
default radius).

=item Debug

C<Debug> is a string (defaults to an empty string). If the substring
"C<url>" is found anywhere in the string, the url of the Yahoo! request is
printed on stderr. If "C<xml>", the raw xml received is printed to stderr.
If "C<hash>", the raw Perl hash, as converted from the XML, is Data::Dump'd
to stderr.

Thus, to print all debugging, you'd set C<Debug> to a value such as "C<url
xml hash>".

=item AutoContinue

A boolean (default off). If true, turns on the B<potentially dangerous>
auto-continuation, as described in the docs for C<NextResult> in
Yahoo::Search::Response.

=back

=head1 Class Hierarchy Details

The Y! Search API class system supports the following objects (all loaded
as needed via Yahoo::Search):

  Yahoo::Search
  Yahoo::Search::Request
  Yahoo::Search::Response
  Yahoo::Search::Result

Here is a summary of them:

=over 10

=item  Yahoo::Search

A "search engine" object which can hold user-specified default values for
search-query arguments. Often not used explicitly.

=item  Yahoo::Search::Request

An object which holds the information needed to make one search-query
request. Often not used explicitly.

=item  Yahoo::Search::Response

An object which holds the results of a query (including a bunch of
C<Result> objects).

=item  Yahoo::Search::Result

An object representing one query result (one image, web page, etc., as
appropriate to the original search space).

=back

=head1 "The Long Way", and Common Practice

The explicit way to perform a query and access the results is to first
create a "Search Engine" object:

  my $SearchEngine = Yahoo::Search->new();

Optionally, you can provide C<new> with key/value pairs as described in the
I<Query arguments> section above. Those values will then be available as
default values during subsequent request creation. (More on this later.)

You then use the search-engine object to create a request:

  my $Request = $SearchEngine->Request(Doc => Britney);

You then actually make the request, getting a response:

  my $Response = $Request->Fetch();

You can then access the set of C<Result> objects in a number of ways,
either all at once

  my @Results = $Response->Results();

or iteratively:


  while (my $Result = $Response->NextResult) {
               :
               :
  }

B<In Practice....>

In practice, one often does not need to go through all these steps
explicitly. The only reason to create a search-engine object, for example,
is to hold default overrides (to be made available to subsequent requests
made via the search-engine object). For example:

   use Yahoo::Search;
   my $SearchEngine = Yahoo::Search->new(AppId      => "Bobs Fish Mart",
                                         Count      => 25,
                                         AllowAdult => 1,
                                         PostalCode => 95014);

Now, calls to the various query functions (C<Query>, C<Results>) via this
C<$SearchEngine> will use these defaults (I<Image> searches, for example,
will be with C<AllowAdult> set to true, and I<Local> searches will be
centered at ZIP code 95014.) All will return up to 25 results.

In this example:

   my @Results = $SearchEngine->Results(Image => "Britney",
                                        Count => 20);

The query is made with C<AppId> as 'C<Bobs_Fish_Mart>' and C<AllowAdult>
true (both via C<$SearchEngine>), but C<Count> is 20 because explicit args
override the default in C<$SearchEngine>. The C<PostalCode> arg does not
apply too an I<Image> search, so the default provided from C<SearchEngine>
is not needed with this particular query.

B<Defaults on the 'use' line>

You can also provide the same defaults on the C<use> line. The following
example has the same result as the previous one:

   use Yahoo::Search AppId      => 'Bobs Fish Mart',
                     Count      => 25,
                     AllowAdult => 1,
                     PostalCode => 95014;

   my @Results = Yahoo::Search->Results(Image => "Britney",
                                        Count => 20);

=head1 Functions and Methods

Here, finally, are the functions and methods provided by Yahoo::Search.
In all cases, "...args..." are any of the key/value pairs listed in the
I<Query arguments> section of this document (e.g. "Count => 20")


=over 4

=item $SearchEngine = Yahoo::Search->new(...args...)

Creates a search-engine object (a container for defaults).
On error, sets C<$@> and returns nothing.



=item $Request = $SearchEngine->Request($space => $query, ...args...)

=item $Request = Yahoo::Search->Request($space => $query, ...args...)

Creates a C<Request> object representing a search of the named search space
(I<Doc>, I<Image>, etc.) of the given query string.

On error, sets C<$@> and returns nothing.

B<Note>: all arguments are in key/value pairs, but the C<$space>/C<$query>
pair (which is required) is required to appear first.




=item $Response = $SearchEngine->Query($space => $query, ...args...)

=item $Response = Yahoo::Search->Query($space => $query, ...args...)

Creates an implicit C<Request> object, and fetches it, returning the
resulting C<Response>.

On error, sets C<$@> and returns nothing.

B<Note>: all arguments are in key/value pairs, but the C<$space>/C<$query>
pair (which is required) is required to appear first.





=item @Results = $SearchEngine->Results($space => $query, ...args...)

=item @Results = Yahoo::Search->Results($space => $query, ...args...)

Creates an implicit C<Request> object, then C<Response> object,
in the end returning a list of C<Result> objects.

On error, sets C<$@> and returns nothing.

B<Note>: all arguments are in key/value pairs, but the C<$space>/C<$query>
pair (which is required) is required to appear first.




=item @links = $SearchEngine->Links($space => $query, ...args...)

=item @links = Yahoo::Search->Links($space => $query, ...args...)

A super shortcut which goes directly from the query args to a list of

  <a href=...>...</a>

links. Essentially,

    map { $_->Link } Yahoo::Search->Results($space => $query, ...args...);

or, more explicitly:

    map { $_->Link } Yahoo::Search->new()->Request($space => $query, ...args...)->Fetch->Results(@_);

See C<Link> in the documentation for Yahoo::Search::Result.

B<Note>: all arguments are in key/value pairs, but the C<$space>/C<$query>
pair (which is required) is required to appear first.





=item @links = $SearchEngine->Terms($space => $query, ...args...)

=item @links = Yahoo::Search->Terms($space => $query, ...args...)

A super shortcut for I<Spell> and I<Related> search spaces, returns the
list of spelling-or related-search suggestions, respectively.

B<Note>: all arguments are in key/value pairs, but the C<$space>/C<$query>
pair (which is required) is required to appear first.





=item @html = $SearchEngine->HtmlResults($space => $query, ...args...)

=item @html = Yahoo::Search->HtmlResults($space => $query, ...args...)

Like C<Links>, but returns a list of html strings (one representing each
result). See C<as_html> in the documentation for Yahoo::Search::Result.

A simple result display might look like

   print join "<p>", Yahoo::Search->HtmlResults(....);

or, perhaps

   if (my @HTML = Yahoo::Search->HtmlResults(....))
   {
      print "<ul>";
      for my $html (@HTML) {
         print "<li>", $html;
      }
      print "</ul>";
   }

As an example, here's a complete CGI which shows results from an
image-search, where the search term is in the 'C<s>' query string:

   #!/usr/local/bin/perl -w
   use CGI;
   my $cgi = new CGI;
   print $cgi->header();

   use Yahoo::Search AppId => 'my-search-app';
   if (my $term = $cgi->param('s')) {
       print join "<p>", Yahoo::Search->HtmlResults(Img => $term);
   }

The results, however, do look better with some style-sheet attention, such
as:

  <style>
    .yResult { display: block; border: #CCF 3px solid ; padding:10px }
    .yLink   { }
    .yTitle  { display:none }
    .yImg    { border: solid 1px }
    .yUrl    { display:none }
    .yMeta   { font-size: 80% }
    .ySrcUrl { }
    .ySum    { font-family: arial; font-size: 90% }
  </style>



B<Note>: all arguments are in key/value pairs, but the C<$space>/C<$query>
pair (which is required) is required to appear first.



=item @html = $SearchEngine->MaxCount($space)

=item @html = Yahoo::Search->MaxCount($space)

Returns the maximum allowed C<Count> query-argument for the given search space.



=item $SearchEngine->Default($key [ => $val ]);

If a new value is given, update the <$SearchEngine>'s value for the named
C<$key>.

In either case, the old value for C<$key> in effect is returned. If the
C<$SearchEngine> had a previous value, it is returned. Otherwise, the
global value in effect is returned.

As always, the key is from among those mentioned in the I<Query arguments>
section above.

The old value is returned.


=item Yahoo::Search->Default($key [ => $val ]);

Update or, if no new value is given, check the global default value for the
named argument. The key is from among those mentioned in the I<Query
examples> section above, as well as C<AutoCarp> (discussed below).

=back


=head1 Defaults and Default Overrides

All key/value pairs mentioned in the I<Query arguments> section may appear
on the C<use> line, in the call to the C<new> constructor, or in requests
that create a query explicitly or implicitly (C<Request>, C<Query>,
C<Results>, C<Links>, or C<HtmlResults>).

Each argument's value takes the first of the following which applies
(listed in order of precedence):

=over 6

=item 4)

The actual arguments to a function which creates (explicitly or implicitly)
a request.

=item 3)

Search-engine default overrides, set when the Yahoo::Search C<new>
constructor is used to create a search-engine object, or when that object's
C<Default> method is called.

=item 2)

Global default overrides, set on the C<use> line or via

 Yahoo::Search->Default()

=item 1)

Defaults hard-coded into these packages (e.g. C<Count> defaults to 10).

=back

It's particularly convenient to put the C<AppId> on the C<use> line,
e.g.

   use Yahoo::Search AppId => 'just testing';

=head1 AutoCarp

By default, detected errors that would be classified as programming errors
(e.g. use of incorrect args) are automatically spit out to stderr besides
being returned via C<$@>. This can be turned off via

  use Yahoo::Search AutoCarp => 0;

or

 Yahoo::Search->Default(AutoCarp => 0);

The default of true is somewhat obnoxious, but hopefully helps create
better programs by forcing the programmer to actively think about error
checking (if even long enough to turn off error reporting).

=head1 Copyright

Copyright (C) 2005 Yahoo! Inc.

=head1 Author

Jeffrey Friedl (jfriedl@yahoo.com)

$Id: Search.pm 2 2005-01-28 04:27:46Z jfriedl $

=cut
