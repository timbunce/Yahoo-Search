package Yahoo::Search::XML;
use strict;

=head1 NAME

Yahoo::Search::XML -- simple routines for parsing XML from Yahoo! Search.

=head1 DESCRIPTION

The XML sent back from Yahoo! is fairly simple, and is guaranteed to be
well formed, so we really don't need much more than to make the data easily
available. I'd like to use XML::Simple, but it uses XML::Parser, which
suffers from crippling memory leaks (in one test, 36k was lost with each
parsing of a 7k xml file), so I've rolled my own simple version that might
be called, uh, XML::SuperDuperSimple.

The end result is identical to what XML::Simple would produce, at least for
the XML the Yahoo! sends back. It may well be useful for other things that
use a similarly small subset of XML notation. This does not support
comments or CDATA, for example, because Yahoo! doesn't send it back.

This package is also much faster than XML::Simple / XML::Parser, producing
the same output 41 times faster, in my tests. That's the benefit of not
having to handle everything, I guess.

=head1 AUTHOR

Jeffrey Friedl <jfriedl@yahoo.com>
Kyoto, Japan
Feb 2005

=cut

my @stack;

##
## Process a start tag.
##
sub Start
{
    my ($tag, %attr) = @_;

    my $node = {
                  Tag => $tag,
                  Char => "",
               };

    if (%attr) {
        $node->{Data} = \%attr;
    }

    push @stack, $node;
}

##
## Process raw text
##
sub Char
{
    my ($str) = @_;
    $stack[-1]->{Char} .= $str;
}


##
## Process an end tag
##
sub End
{
    my ($tag) = @_;
    my $node = pop @stack;

    my $val;

    if ($node->{Data})
    {
        die "oops" if $node->{Char} ne "";
        $val = $node->{Data};
    }
    elsif ($node->{Char} ne "")
    {
        die "oops" if $node->{Data};
        $val = $node->{Char};
    }
    else
    {
        $val = "";
    }

    ##
    ## Shove this data ($val) into the previous node, named for this $tag
    ##
    if (not $stack[-1]->{Data}->{$node->{Tag}}) {
        $stack[-1]->{Data}->{$node->{Tag}} = $val;
    } elsif  (ref($stack[-1]->{Data}->{$node->{Tag}}) eq "ARRAY") {
        push @{ $stack[-1]->{Data}->{$node->{Tag}} }, $val;
    } else {
        $stack[-1]->{Data}->{$node->{Tag}} = [ $stack[-1]->{Data}->{$node->{Tag}}, $val ];
    }
}

my %EntityDecode =
(
  amp  => '&',
  lt   => '<',
  gt   => '>',
  apos => "'",
  quot => '"', #"
);

sub _entity($)
{
    my $name = shift;
    if (my $val = $EntityDecode{$name}) {
        return $val;
    } elsif ($val =~ m/^\d+$/) {
        return chr($val);
    } else {
        die "unknown entity &$name;";
    }
}

sub de_grok($)
{
    my $text = shift;
    $text =~ s/&([^;]+);/_entity($1)/gxe;
    return $text;
}

sub Parse($)
{
    my $xml = shift;

    @stack = {};

    ## get rid of leading <?xml> tag
    $xml =~ m/\A <\?xml.*?> /xgc;

    while (pos($xml) < length($xml))
    {
        ##
        ## Nab <open>, </close>, and <unary/> tags...
        ##
        if ($xml =~ m{\G
                      <(/?)       # $1 - true if an ending tag
                       (\w+)      # $2 - tag name
                       (\s[^>]*)? # $3 - attributes (and possible final '/')
                      >}xgc)
        {
            my ($IsEnd, $TagName, $Attribs) = ($1, $2, $3);

            my $IsImmediateEnd = 1 if ($Attribs and $Attribs =~ s{/$}{});

            if ($IsEnd) {
                End($TagName);
            } else {
                my %A;
                if ($Attribs)
                {
                    while ($Attribs =~ m/(\w+)=(?: "([^\"]*)" | '([^\']*)'  )/xg) {
                        $A{$1} = de_grok(defined($3) ? $3 : $2);
                    }
                }
                Start($TagName, %A);
                if ($IsImmediateEnd) {
                    End($TagName);
                }
            }
        }
        elsif ($xml =~ m/\G<!--.*?-->/xgc)
        {
            ## comment -- ignore
        }
        ##
        ## Nab raw text  / entities
        ##
        elsif ($xml =~ m/\G ([^<>]+)/xgc)
        {
            Char(de_grok($1));
        }
        else
        {
            my ($str) = $xml =~ m/\G(.{1,40})/;
            $str .= "..." if length($str) == 40;
            die "bad XML parse at \"$str\"";
        }
    }

    #use Data::Dumper; print Data::Dumper::Dumper(\@stack), "\n";
    die "oops" if @stack != 1;
    die "oops" if not $stack[0]->{Data};
    die "oops" if keys(%{ $stack[0]->{Data}} ) != 1;
    my ($tree) = values(%{$stack[0]->{Data}});
    return $tree;
}

1;

