package POE::Component::WWW::Google::PageRank;

use strict;
use warnings;

# VERSION

use POE (qw( Wheel::Run  Filter::Reference  Filter::Line ));
use Carp;
use WWW::Google::PageRank;

sub spawn {
    my $package = shift;

    croak "$package requires an even number of arguments"
        if @_ & 1;

    my %params = @_;

    $params{ lc $_ } = delete $params{ $_ } for keys %params;

    delete $params{options}
        unless ref $params{options} eq 'HASH';

    my $self = bless \%params, $package;

    $self->{session_id} = POE::Session->create(
        object_states => [
            $self => {
                rank     => '_rank',
                shutdown => '_shutdown',
            },
            $self => [
                qw(
                    _start
                    _child_error
                    _child_closed
                    _child_stderr
                    _child_stdout
                    _sig_chld
                )
            ],
        ],
        ( defined $params{options} ? ( options => $params{options} ) : () )
    )->ID;

    return $self;
}

sub _start {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $self->{session_id} = $_[SESSION]->ID();

    if ( $self->{alias} ) {
        $kernel->alias_set( $self->{alias} );
    }
    else {
        $kernel->refcount_increment( $self->{session_id} => __PACKAGE__ );
    }

    $self->{wheel} = POE::Wheel::Run->new(
        Program => \&_rank_wheel,
        ErrorEvent => '_child_error',
        CloseEvent => '_child_closed',
        StderrEvent => '_child_stderr',
        StdoutEvent => '_child_stdout',
        StdioFilter => POE::Filter::Reference->new,
        StderrFilter => POE::Filter::Line->new,
        ( $^O eq 'MSWin32' ? ( CloseOnCall => 0 ) : ( CloseOnCall => 1 ) ),
    );

    $kernel->yield('shutdown')
        unless $self->{wheel};

    $kernel->sig_child( $self->{wheel}->PID, '_sig_chld' );

    undef;
}

sub _sig_chld {
    $poe_kernel->sig_handled;
}

sub session_id {
    return $_[0]->{session_id};
}

sub rank {
    my $self = shift;
    $poe_kernel->post( $self->{session_id} => 'rank' => @_ );
}

sub _rank {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    my $sender = $_[SENDER]->ID;

    return
        if $self->{shutdown};

    my $args;

    if ( ref $_[ARG0] eq 'HASH' ) {
        $args = { %{ $_[ARG0] } };
    }
    else {
        warn "First parameter must be a hashref... trying to adjust";
        $args = { @_[ARG0 .. $#_] };
    }

    $args->{ lc $_ } = delete $args->{ $_ }
        for grep { !/^_/ } keys %{ $args };

    unless ( $args->{event} ) {
        warn "No `event` parameter was specified";
        return;
    }

    unless ( $args->{page} ) {
        warn "No `page` parameter was specified";
        return;
    }

    # not sure if this is mandatory but WWW::Google:PageRank rejects URIs
    # not matching this regex, so we'll fix it up and hope it won't
    # eat us
    unless ( $args->{page} =~ m#^https?://#i ) {
        warn "Parameter `page` does not match m#^https?://#i"
            if $self->{debug};

        $args->{page} = "http://$args->{page}";
    }

    if ( $args->{session} ) {
        if ( my $ref = $kernel->alias_resolve( $args->{session} ) ) {
            $args->{sender} = $ref->ID;
        }
        else {
            warn "Parameter `session` did not resolve to an active POE"
                    . " session, aborting";
            return;
        }
    }
    else {
        $args->{sender} = $sender;
    }

    $kernel->refcount_increment( $args->{sender} => __PACKAGE__ );
    $self->{wheel}->put( $args );

    undef;
}

sub shutdown {
    my $self = shift;
    $poe_kernel->post( $self->{session_id} => 'shutdown' => @_ );
}

sub _shutdown {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $kernel->alarm_remove_all;
    $kernel->alias_remove( $_ ) for $kernel->alias_list;
    $kernel->refcount_decrement( $self->{session_id} => __PACKAGE__ )
        unless $self->{alias};

    $self->{shutdown} = 1;
    $self->{wheel}->shutdown_stdin
        if $self->{wheel};

    undef;
}
sub _child_closed {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];

    warn "Got _child_closed() (@_[ARG0..$#_])"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_error {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];

    warn "Got _child_error() (@_[ARG0..$#_])"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_stderr {
    my ( $kernel, $self, $input ) = @_[ KERNEL, OBJECT, ARG0 ];
    warn "Got _child_stderr: $input\n"
        if $self->{debug};

    undef;
}

sub _child_stdout {
    my ( $kernel, $self, $input ) = @_[ KERNEL, OBJECT, ARG0 ];

    my $session = delete $input->{sender};
    my $event   = delete $input->{event};

    $kernel->post( $session => $event => $input );
    $kernel->refcount_decrement( $session => __PACKAGE__ );

    undef;
}

sub _rank_wheel {
    if ( $^O eq 'MSWin32' ) {
        binmode STDIN;
        binmode STDOUT;
    }

    my $raw;
    my $size = 4096;
    my $filter = POE::Filter::Reference->new;

    while ( sysread STDIN, $raw, $size ) {
        my $requests = $filter->get( [ $raw ] );
        foreach my $req ( @$requests ) {
            my $page_rank
                = WWW::Google::PageRank->new( %{ $req->{options} || {} } );

            @{ $req }{ qw(rank response) }
                = $page_rank->get( $req->{page} );

            unless ( $req->{response}->is_success ) {
                @{ $req }{ qw(rank error) }
                    = ( undef, $req->{response}->status_line );
            }

            my $response = $filter->put( [ $req ] );
            print STDOUT @$response;
        }
    }
}

1;
__END__

=encoding utf8

=head1 NAME

POE::Component::WWW::Google::PageRank - A non-blocking wrapper for
L<WWW::Google::PageRank>

=head1 SYNOPSIS

    use strict;
    use warnings;

    use POE qw(Component::WWW::Google::PageRank);

    my $poco
        = POE::Component::WWW::Google::PageRank->spawn( alias => 'ranker' );

    POE::Session->create(
        package_states => [
            'main' => [
                qw( _start got_rank )
            ],
        ],
    );

    $poe_kernel->run;

    sub _start {
        $poe_kernel->post( ranker => rank => {
                page => 'http://zoffix.com',
                event   => 'got_rank',
                _random => 'foos',
            }
        );
    }

    sub got_rank {
        my ( $kernel, $result ) = @_[ KERNEL, ARG0 ];

        if ( $result->{error} ) {
            print "ZOMG! An error: $result->{error}\n";
        }
        else {
            print "The rank for $result->{page} is $result->{rank}\n";
        }

        print "Oh, BTW: $result->{_random}\n";

        $poco->shutdown;
    }

=head1 DESCRIPTION

Module is a simple non-blocking L<POE> wrapper around
L<WWW::Google::PageRank>

=head2 CONSTRUCTOR

    my $poco = POE::Component::WWW::Google::PageRank->spawn;

    POE::Component::WWW::Google::PageRank->spawn( alias => 'ranker' );

Returns a PoCo object. Takes three I<optional> arguments:

=head2 alias

    POE::Component::WWW::Google::PageRank->spawn( alias => 'ranker' );

Specifies a POE Kernel alias for the component

=head2 options

    POE::Component::WWW::Google::PageRank->spawn(
        options => {
            trace => 1,
            default => 1,
        },
    );

A hashref of POE Session options to pass to the component's session.

=head2 debug

    POE::Component::WWW::Google::PageRank->spawn( debug => 1 );

When set to a true value turns on output of debug messages.

=head1 METHODS

These are the object-oriented methods of the components.

=head2 rank

    $poco->rank( {
            page  => 'http://zoffix.com',
            event => 'got_rank',
        }
    );

Takes hashref of options. See C<rank> event below for description.

=head2 session_id

    my $ranker_id = $poco->session_id;

Takes no arguments. Returns component's session ID.

=head2 shutdown

    $poco->shutdown;

Takes no arguments. Shuts down the component.

=head1 ACCEPTED EVENTS

=head2 rank

    $poe_kernel->post( ranker => rank => {
            page          => 'http://zoffix.com',
            event         => 'got_rank',
            session       => $some_other_session,
            _random       => 'foos',
            options       => {
                ua      => 'Better not touch this',
                timeout => 10,
            }
        }
    );

Instructs the component to get a page rank. Options are passed in a hashref
with keys as follows:

=head3 page

    { page => 'http://zoffix.com' }

B<Mandatory>. The page for which we need to get the rank.

=head3 event

    { event => 'got_rank' }

B<Mandatory>. An event to send the result to.

=head3 session

    { session => $some_other_session_ref }

    { session => 'some_alias' }

    { session => $session->ID }

B<Optional>. An alternative session alias, reference or ID that the
response should be sent to, defaults to sending session.

=head3 options

    { options => { timeout => 10 } }

B<Optional>. The value must be a hashref and these options will go
directly to
L<WWW::Google::PageRank> C<new()> method. See documentation for
L<WWW::Google::PageRank> for more information.

=head3 user defined

B<Optional>. Any keys starting with C<_> (underscore) will not affect the
component and will be passed back in the result intact.

=head2 shutdown

    $poe_kernel->post( ranker => 'shutdown' );

Takes no arguments. Tells the component to shut itself down.

=head1 OUTPUT

    sub got_rank {
        my ( $kernel, $result ) = @_[ KERNEL, ARG0 ];

        if ( $result->{error} ) {
            print "ZOMG! An error: $result->{error}\n";
        }
        else {
            print "The rank for $result->{page} is $result->{rank}\n";
        }

        print "Oh, BTW: $result->{_random}\n";

        $poco->shutdown;
    }


The result will be posted to the event and (optional) session specified in
the arguments to the C<rank> (event or method). The result, in the form
of a hashref, will be passed in ARG0. The keys of that hashref are as
follows

=head3 rank

    print "Rank is: $result->{rank}\n";

The C<rank> key will contain the page rank of the page passed to C<rank>
event/method (note that the page is also in C<$result-E<gt>{page}>).
If an error occurred it will be undefined and C<error> key will also be
present.

=head3 error

    if ( $result->{error} ) {
        print "Error while fetching :( $result->{error}\n";
    }
    else {
        print "Rank: $result->{rank}\n";
    }

If an error occurred during the query the C<error> key will be present
with L<LWP::UserAgent> C<status_line()>'s message.

=head3 response

    print "The status of request: " .
        $result->{response}->status_line . "\n";

This key contains an L<HTTP::Response> object returned by L<LWP::UserAgent>
when we were fetching for page rank.

=head3 user defined

    print "$result->{_name}, the answer is $result->{out}\n";

Any arguments beginning with C<_> (underscore) passed into the C<rank>
event/method will be present intact in the result.

=head1 REPOSITORY

Fork this module on GitHub:
L<https://github.com/zoffixznet/POE-Component-Bundle-WebDevelopment>

=head1 BUGS

To report bugs or request features, please use
L<https://github.com/zoffixznet/POE-Component-Bundle-WebDevelopment/issues>

If you can't access GitHub, you can email your request
to C<bug-POE-Component-Bundle-WebDevelopment at rt.cpan.org>

=head1 AUTHOR

Zoffix Znet <zoffix at cpan.org>
(L<http://zoffix.com/>, L<http://haslayout.net/>)

=head1 LICENSE

You can use and distribute this module under the same terms as Perl itself.
See the C<LICENSE> file included in this distribution for complete
details.

=cut