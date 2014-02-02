#!/usr/bin/env perl

use Test::More tests => 17;
BEGIN {
    use_ok('POE');
    use_ok('POE::Filter::Reference');
    use_ok('POE::Filter::Line');
    use_ok('POE::Wheel::Run');
    use_ok('WWW::Google::PageRank');
    use_ok('Carp');
    use_ok('POE::Component::WWW::Google::PageRank');
};

diag( "Testing POE::Component::WWW::Google::PageRank $POE::Component::WWW::Google::PageRank::VERSION, Perl $], $^X" );

use POE qw(Component::WWW::Google::PageRank);

my $poco = POE::Component::WWW::Google::PageRank->spawn( alias => 'ranker' );

can_ok($poco, qw(rank shutdown session_id));

POE::Session->create(
    package_states => [
        'main' => [ qw( _start rank_result rank_method_result ) ],
    ],
);

POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->alias_set('test_session');
        },
        got_rank => \&got_rank,
    }
);
my $tested_tests = 0;
$poe_kernel->run;

sub _start {
    $poe_kernel->alias_set('foo');
    $poe_kernel->post( ranker => rank => {
            page => 'http://google.com',
            event => 'rank_result',
            _random_name => 'random_value',
        }
    );
    print "\nPosted a rank event. Trying to send a query "
        . "with OO interface...\n";
    $poco->rank( {
            page => 'http://google.com',
            event => 'rank_method_result',
            _user => 'test',
        }
    );

    print "\nNow sending a request with 'session' parameter\n";
    $poco->rank(
        {
            page  => 'http://yahoo.com',
            event => 'got_rank',
            session => 'test_session',
            _user   => 'Joe Shmoe',
        }
    );

}

sub rank_method_result {
    my $result = $_[ARG0];
    ok(
        ref $result eq 'HASH',
        "(method call) Expecting result as a hashref."
            . " And ref(\$result) gives us: " . ref $result
    );

    if ( $result->{error} ) {
        ok(
            !defined ($result->{rank}),
            "(method call) Got error. Result should be undefined"
                . " Error text: `$result->{error}`"
        );
    }
    else {
        ok(
            $result->{rank} == 9,
            "(method call) Did we get correct result? "
                . "(expecting: '10' "
                . "got '$result->{rank}')"
        );
        ok(
            $result->{_user} eq 'test',
            "(method call) user defined args (expecting: "
                . "'test' "
                . "got '$result->{_user}')"
        );
    }

    $poco->shutdown if ++$tested_tests eq 3;
}

sub rank_result {
    my ( $kernel, $result ) = @_[ KERNEL, ARG0 ];

    ok(
        ref $result eq 'HASH',
        "(event call) expecting result as a hashref in"
            . " rank_result()."
            . " And ref(\$result) gives us: " . ref $result
    );

    if ( $result->{error} ) {
        ok(
            !defined ($result->{rank}),
            "(event call) Got error. Result should be undefined."
                . " Error text: `$result->{error}`"
        );
    }
    else {
        ok(
            $result->{rank} == 9,
            "(event call) Did we get correct result? "
                . "(expecting: '10' "
                . "got '$result->{rank}')"
        );

        ok(
            $result->{_random_name} eq 'random_value',
            "(event call) User defined args (expecting: 'random_value' "
                . "got '$result->{_random_name}')"
        );
    }

    $poco->shutdown if ++$tested_tests eq 3;
}

sub got_rank {
    my ( $kernel, $result ) = @_[ KERNEL, ARG0 ];

    print "\n###  Got results from another session:\n";

    ok(
        ref $result eq 'HASH',
        "expecting result as a hashref in"
            . " got_rank()."
            . " And ref(\$result) gives us: " . ref $result
    );

    if ( $result->{error} ) {
        ok(
            !defined ($result->{rank}),
            "Got error. Result should be undefined."
                . " Error text: `$result->{error}`"
        );
    }
    else {
        ok(
            $result->{rank} =~ /^1?\d$/,
            "Did we get correct result? "
                . "(expecting a number from 0 to 10 "
                . "got '$result->{rank}')"
        );

        ok(
            $result->{_user} eq 'Joe Shmoe',
            "User defined args (expecting: 'Joe Shmoe' "
                . "got '$result->{_user}')"
        );
    }

    $poco->shutdown if ++$tested_tests eq 3;
}
