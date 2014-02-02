#!perl

use strict;
use warnings;

# VERSION

die "Usage: perl rank.pl <page_to_rank>\n"
    unless @ARGV;

use lib qw(../lib  lib);
use POE qw(Component::WWW::Google::PageRank);

my $Page_to_rank = shift;
my $poco = POE::Component::WWW::Google::PageRank->spawn;

POE::Session->create(
    package_states => [
        main => [ qw(_start rank) ],
    ],
);

$poe_kernel->run;

sub _start {
    $poco->rank( { event => 'rank', page => $Page_to_rank } );
}

sub rank {
    my $result = $_[ARG0];
    if ( $result->{error} ) {
        print "Error: $result->{error}\n";
    }
    else {
        print "The rank for $result->{page} is $result->{rank}\n";
    }

    $poco->shutdown;
}
