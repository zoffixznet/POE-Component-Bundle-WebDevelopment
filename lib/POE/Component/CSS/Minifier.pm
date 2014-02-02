package POE::Component::CSS::Minifier;

use warnings;
use strict;

# VERSION

use POE;
use base 'POE::Component::NonBlockingWrapper::Base';
use CSS::Minifier;
use LWP::UserAgent;

sub _methods_define {
    return ( minify => '_wheel_entry' );
}

sub minify {
    $poe_kernel->post( shift->{session_id} => minify => @_ );
}

sub _process_request {
    my ( $self, $in_ref ) = @_;

    eval {
        if ( defined $in_ref->{infile} ) {
            open my $in, '<', $in_ref->{infile}
                or $in_ref->{error} = "infile error [$!]"
                and return;


            if ( defined $in_ref->{outfile} ) {
                open my $out, '>', $in_ref->{outfile}
                    or $in_ref->{error} = "outfile error [$!]"
                    and return;

                CSS::Minifier::minify( input => $in, outfile => $out );
            }
            else {
                $in_ref->{out} = CSS::Minifier::minify( input => $in );
            }
        }
        elsif ( $in_ref->{uri} ) {
            my $response
            = LWP::UserAgent->new( %{ $self->{ua_args} || {} } )->get( $in_ref->{uri} );

            if ( $response->is_success ) {
                if ( defined $in_ref->{outfile} ) {
                    open my $out, '>', $in_ref->{outfile}
                        or $in_ref->{error} = "outfile error [$!]"
                        and return;

                    CSS::Minifier::minify(
                        input => $response->decoded_content,
                        outfile => $out,
                    );
                }
                else {
                    $in_ref->{out} = CSS::Minifier::minify( input => $response->decoded_content );
                }
            }
            else {
                $in_ref->{error} = $response->status_line;
            }
        }
        else {
            $in_ref->{out} = CSS::Minifier::minify( input => $in_ref->{in} );
        }
    };
    $@ and $in_ref->{out} = "ERROR: $@";
}

1;
__END__

=encoding utf8

=head1 NAME

POE::Component::CSS::Minifier - non-blocking wrapper around CSS::Minifier with URI fetching abilities

=head1 SYNOPSIS

    use strict;
    use warnings;

    use POE qw/Component::CSS::Minifier/;

    my $poco = POE::Component::CSS::Minifier->spawn;

    POE::Session->create( package_states => [ main => [qw(_start results)] ], );

    $poe_kernel->run;

    sub _start {
        $poco->minify(
                event   => 'results',
                uri     => 'http://zoffix.com/main.css',
                outfile => 'out.css',
            }
        );
    }

    sub results {
        if ( $_[ARG0]->{error} ) {
            print "Error: $_[ARG0]->{error}\n";
        }
        else {
            print "Minified ito $_[ARG0]->{outfile}\n";
        }
        $poco->shutdown;
    }

Using event based interface is also possible of course.

=head1 DESCRIPTION

The module is a non-blocking wrapper around L<CSS::Minifier>, which provides interface to
strip useless spaces from CSS code. The wrapper also provides additional functionality to
fetch CSS from URI.

=head1 CONSTRUCTOR

=head2 C<spawn>

    my $poco = POE::Component::CSS::Minifier->spawn;

    POE::Component::CSS::Minifier->spawn(
        alias => 'mini',
        ua_args => { timeout => 30 },
        options => {
            debug => 1,
            trace => 1,
            # POE::Session arguments for the component
        },
        debug => 1, # output some debug info
    );

The C<spawn> method returns a
POE::Component::CSS::Minifier object. It takes a few arguments,
I<all of which are optional>. The possible arguments are as follows:

=head3 C<alias>

    ->spawn( alias => 'mini' );

B<Optional>. Specifies a POE Kernel alias for the component.

=head3 C<ua_args>

    ->spawn( ua_args => { timeout => 30 }, );

B<Optional>. Takes a hashref as an argument that will be directly dereferenced into
L<LWP::UserAgent>'s constructor when C<uri> argument in C<minify> event/method is used
as input. B<Defaults to:> empty hashref.

=head3 C<options>

    ->spawn(
        options => {
            trace => 1,
            default => 1,
        },
    );

B<Optional>.
A hashref of POE Session options to pass to the component's session.

=head3 C<debug>

    ->spawn(
        debug => 1
    );

When set to a true value turns on output of debug messages. B<Defaults to:>
C<0>.

=head1 METHODS

=head2 C<minify>

    $poco->minify( {
            event       => 'event_for_output',
            uri         => 'http://zoffix.com/main.css',
            outfile     => 'minified.css',
            _blah       => 'pooh!',
            session     => 'other',
        }
    );

Takes a hashref as an argument, does not return a sensible return value.
See C<minify> event's description for more information.

=head2 C<session_id>

    my $poco_id = $poco->session_id;

Takes no arguments. Returns component's session ID.

=head2 C<shutdown>

    $poco->shutdown;

Takes no arguments. Shuts down the component.

=head1 ACCEPTED EVENTS

=head2 C<minify>

    $poe_kernel->post( mini => minify => {
            event       => 'event_for_output',
            uri         => 'http://zoffix.com/main.css',
            outfile     => 'minified.css', # optional
            _blah       => 'pooh!',
            session     => 'other',
        }
    );

    # or

    $poe_kernel->post( mini => minify => {
            event       => 'event_for_output',
            infile      => 'in.css',
            outfile     => 'minified.css', # optional
            _blah       => 'pooh!',
            session     => 'other',
        }
    );

    # or

    $poe_kernel->post( mini => minify => {
            event       => 'event_for_output',
            in          => 'div:hover { border: 1px solid #000; }',
            outfile     => 'minified.css', # optional
            _blah       => 'pooh!',
            session     => 'other',
        }
    );

Instructs the component to strip useless spaces from CSS code. Takes a hashref as an
argument, the possible keys/value of that hashref are as follows:

=head3 C<event>

    { event => 'results_event', }

B<Mandatory>. Specifies the name of the event to emit when results are
ready. See OUTPUT section for more information.

=head3 C<in>

    { in => 'div:hover { border: 1px solid #000; }' }

B<Optional>. One of the methods to give input. Takes a string with CSS code to
"minify" as an argument.

=head3 C<uri>

    { uri => 'http://zoffix.com/main.css' }

B<Optional>. One of the methods to give input. Takes a URI as a value that will be fetched
and serve as CSS code to "minify".

=head3 C<infile>

    { infile => 'in.css' }

B<Optional>. One of the methods to give input. Takes a filename as an argument. The
file will be opened and the filehandle will be given to C<minify()> function of
L<CSS::Minifier> to serve as CSS code to "minify".

=head3 C<outfile>

    { outfile => 'minified.css' }

B<Optional>. When specified, the "minified" CSS code will be written to the file, filename
of which you specify in C<outfile> argument. Note: file will be created if does not exist and
completely destroyed without a warning if it does exist. If not specified the
minified CSS code will be passed to the output event handler (see below).

=head3 C<session>

    { session => 'other' }

    { session => $other_session_reference }

    { session => $other_session_ID }

B<Optional>. Takes either an alias, reference or an ID of an alternative
session to send output to.

=head3 user defined

    {
        _user    => 'random',
        _another => 'more',
    }

B<Optional>. Any keys starting with C<_> (underscore) will not affect the
component and will be passed back in the result intact.

=head2 C<shutdown>

    $poe_kernel->post( mini => 'shutdown' );

Takes no arguments. Tells the component to shut itself down.

=head1 OUTPUT

    $VAR1 = {
        'out' => 'div:hover{border:1px solid #000;}',
        'in' => 'div:hover { border: 1px solid #000; }',
        '_blah' => 'foos'
    };

The event handler set up to handle the event which you've specified in
the C<event> argument to C<minify()> method/event will receive input
in the C<$_[ARG0]> in a form of a hashref. The possible keys/value of
that hashref are as follows:

=head2 C<out>

    { 'out' => 'div:hover{border:1px solid #000;}', }

Unless C<outfile> was specified as an argument to C<minify> event/method, the C<out> key
will be present and its value will be minified CSS code.

=head2 C<error>

    { 'error' => 'infile error [No such file or directory]' }

If an error occurred, the C<error> key will be present and its value will be description
of an error. The error could be errors during opening input or output files as well as
network errors when C<uri> argument was given to C<minify> event/method.

=head2 C<in>, C<uri> and C<infile>

    { 'in' => 'div:hover { border: 1px solid #000; }', }

Depending on how you are giving the input to C<minify> event/method, the key you specify in
C<minify> event/method will be present in the output.

=head2 user defined

    { '_blah' => 'foos' }

Any arguments beginning with C<_> (underscore) passed into the C<minify()>
event/method will be present intact in the result.

=head1 SEE ALSO

L<POE>, L<CSS::Minifier>

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