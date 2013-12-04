package POE::Component::IRC::Plugin::YouTube::MovieFindStore;

use warnings;
use strict;

our $VERSION = '0.02';

use File::Spec;
use POE::Component::IRC::Plugin qw( :ALL );
use POE qw(Component::WWW::YouTube::VideoURI);

sub new {
    my $package = shift;
    my %args = @_;
    $args{ lc $_ } = delete $args{ $_ } for keys %args;

    %args = (
        got_uri_event   => 'youtube_got_flv_uri',
        found_uri_event => 'youtube_found_uri',
        resolve         => 1,
        store_event     => 'youtube_stored',
        replace         => qr/\W/,
        replace_char    => '_',
        trigger         => qr/^youtube\s+/i,
        root_store      => 1,

        %args, # override any default values
    );
    
    if ( exists $args{channels} ) {
        if ( ref $args{channels} eq 'ARRAY' ) {
            $args{channels} = { map { lc $_ => 1 } @{ $args{channels} } };
        }
        else {
            warn "Argument `channels` must contain an "
                    . "arrayref.. discarding";

            delete $args{channels};
        }
    }

    return bless \%args, $package;
}

sub PCI_register {
    my ( $self, $irc ) = splice @_, 0, 2;
    
    $self->{irc} = $irc;
    
    $irc->plugin_register( $self, 'SERVER', qw(public) );
    
    $self->{_session_id} = POE::Session->create(
        object_states => [
            $self => [
                qw(
                    _start
                    _shutdown
                    _get_link
                    _got_uri_handler
                    _stored_handler
                )
            ]
        ],
    )->ID;
    
    return 1;
}

sub _start {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $self->{_session_id} = $_[SESSION]->ID();
    POE::Component::WWW::YouTube::VideoURI->spawn( alias => 'tube',
    debug => 1);
    $kernel->refcount_increment( $self->{_session_id}, __PACKAGE__ );
    undef;
}

sub _shutdown {
    my ($kernel, $self) = @_[ KERNEL, OBJECT ];
    $kernel->alarm_remove_all();
    $kernel->refcount_decrement( $self->{_session_id}, __PACKAGE__ );
    undef;
}

sub PCI_unregister {
    my $self = shift;
    
    # Plugin is dying make sure our POE session does as well.
    $poe_kernel->call( $self->{_session_id} => '_shutdown' );
    
    delete $self->{irc};
    
    return 1;
}

sub S_public {
    my ($self,$irc) = splice @_, 0, 2;
    my $who     = ${ $_[0] };
    my $channel = ${ $_[1] }->[0];
    my $what    = ${ $_[2] };
    
    
    return PCI_EAT_NONE
        if ( exists $self->{banned} and $who =~ /$self->{banned}/ )
            or ( exists $self->{users} and $who !~ /$self->{users}/ );

    return PCI_EAT_NONE
        if exists $self->{channels}
            and not exists $self->{channels}{ lc $channel };

    my @links;
    if ( $self->{auto} or $what =~ /$self->{trigger}/ ) {
        @links
        = $what =~ m{
            \b(
                (?: http:// )?
                (?: www\.   )?
                youtube\.com/watch\?
                (?: \S+?& )? # any query parameters that might preceed v=
                v=\S+ # v= the parameter with the movie
            )\b
        }gx;
    }

    return PCI_EAT_NONE unless @links;
    
    $self->{irc}->_send_event( $self->{found_uri_event} => {
            links   => [ @links ],
            who     => $who,
            channel => $channel,
            what    => $what,
        },
    );
    
    if ( $self->{resolve} ) {
        $poe_kernel->post( $self->{_session_id} => _get_link =>  {
                links   => \@links,
                data   => {
                    who     => $who,
                    channel => $channel,
                    what    => $what,
                },
            },
        );
    }
    return $self->{eat} ? PCI_EAT_ALL : PCI_EAT_NONE;
}

sub _get_link {
    my ( $kernel, $self, $data ) = @_[ KERNEL, OBJECT, ARG0 ];
    
    
    foreach my $uri ( @{ $data->{links} } ) {
        if ( 'http://' ne substr $uri, 0, 7 ) {
            $uri = "http://$uri";
        }

        $poe_kernel->post( tube => get_uri => {
                uri   => $uri,
                event => '_got_uri_handler',
                _data => $data->{data},
            }
        );
    }
}

sub _got_uri_handler {
    my ( $kernel, $self, $input ) = @_[ KERNEL, OBJECT, ARG0 ];
    $self->{irc}->_send_event( $self->{got_uri_event} => $input );
    
    if ( $self->{where} ) {
        
        my $title = $input->{title};
        if ( $self->{replace} ) {
            $title = $self->_fix_title( $title );
        }
    
        my $filename = File::Spec->catfile(
            $self->{where},
            $title . '.flv',
        );
    
        if (
            !$self->{root_store}
            or (
                exists $self->{store_users}
                and $input->{_data}{who} =~ /$self->{store_users}/
            )
        ) {
            $kernel->post(
                tube => store => {
                    flv_uri => $input->{out},
                    where   => $filename,
                    title   => $input->{title},
                    store_event => '_stored_handler',
                    _data => $input->{_data},
                }
            );
        }
    }
    
    undef;
}

sub _fix_title {
    my $self  = shift;
    my $title = shift;
    
    my @replace = ref $self->{replace} eq 'ARRAY'
                ? @{  $self->{replace} }
                :  (  $self->{replace} );
    
    my @chars = ref $self->{replace_char} eq 'ARRAY'
              ? @{  $self->{replace_char} }
              :  (  $self->{replace_char} );
    for my $i ( 0 .. $#replace ) {
        eval {
            $title =~ s/$replace[ $i ]/$chars[ $i ]/xg;
        };
        warn "Improper regex for replacement: $@"
            if $@;
    }
    return $title;
}

sub _stored_handler {
    my ( $kernel, $self, $input ) = @_[ KERNEL, OBJECT, ARG0 ];
    $self->{irc}->_send_event( $self->{store_event} => $input );
}

1;



1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

POE::Component::IRC::Plugin::YouTube::MovieFindStore - plugin for finding,
resolving .FLV, and optionally storing YouTube URIs.

=head1 SYNOPSIS

    use strict;
    use warnings;
    
    use POE qw(Component::IRC  Component::IRC::Plugin::YouTube::MovieFindStore);
    
    
    my $irc = POE::Component::IRC->spawn( 
            nick    => 'TubeBot',
            server  => 'irc.freenode.net',
            port    => 6667,
            ircname => 'YouTube Grabber',
    ) or die "Oh noes :( $!";
    
    POE::Session->create(
        package_states => [
            main => [
                qw(
                    _start
                    irc_001
                    youtube_got_uri
                    youtube_stored
                )
            ],
        ],
    );
    
    $poe_kernel->run();
    
    sub _start {
        $irc->yield( register => 'all' );
        
        # register our plugin
        $irc->plugin_add(
            'Tube' => 
                POE::Component::IRC::Plugin::YouTube::MovieFindStore->new(
                    where        => '/home/zoffix/Desktop/tube/',
                    replace      => [ qr/\s+/, qr/[^\w-]/ ],
                    replace_char => [ '-',     '_'        ],
                    trigger      => qr/^tube\s+/i,
                    banned       => qr/aol\.com$/i,
                    users        => qr{unaffiliated/zoffix$},
                    root_store   => 1,
                    store_users  => qr/^Zoffix!/i,
                ) # all arguments are optional
        );
        
        $irc->yield( connect => { } );
        undef;
    }
    
    sub irc_001 {
        my ( $kernel, $sender ) = @_[ KERNEL, SENDER ];
        $kernel->post( $sender => join => '#zofbot' );
        undef;
    }
    
    sub youtube_got_uri {
        my ( $kernel, $input ) = @_[ KERNEL, ARG0 ];
        
        my ( $channel, $who ) = @{ $input->{_data} }{ qw( channel who ) };
        my $nick = ( split /!/, $who )[0];
        
        my $message;
        if ( $input->{error} ) {
            $message = "Error: $input->{error}";
        }
        else {
            $message = sprintf "%s, Title: %s URI: %s FLV: %s",
                            $nick, @$input{ qw( title  uri  out ) };
        }
        $poe_kernel->post( $irc => privmsg => $channel => $message );
    
        undef;
    }
    
    sub youtube_stored {
        my ( $kernel, $input ) = @_[ KERNEL, ARG0 ];
        my ( $channel, $who ) = @{ $input->{_data} }{ qw( channel who ) };
        my $nick = ( split /!/, $who )[0];
    
        my $message;
        if ( $input->{store_error} ) {
            $message =  "$nick, flailed :( $input->{store_error}\n";
        }
        else {
            "$nick, saved as $input->{title} as $input->{where}"
        }
        $poe_kernel->post( $irc => privmsg => $channel => $message );
    }

=head1 DESCRIPTION

The module is a plugin for L<POE::Component::IRC>. It provides a utility
for resolving YouTube's URLs into links pointing to the downloadable
C<.flv> file with an option to mirror the file locally.

=head1 CONSTRUCTOR

    my $tube = POE::Component::IRC::Plugin::YouTube::MovieFindStore->new(
        where        => '/home/zoffix/Desktop/tube/',
        replace      => [ qr/\s+/, qr/[^\w-]/ ],
        replace_char => [ '-',     '_'        ],
        trigger      => qr/^tube\s+/i,
        banned       => qr/aol\.com$/i,
        users        => qr{unaffiliated/zoffix$},
        root_store   => 1,
        store_users  => qr/^Zoffix!/i,
    );
    $irc->plugin_add( CustomTube => $tube );

    my $tube2 = POE::Component::IRC::Plugin::YouTube::MovieFindStore->new;
    $irc->plugin_add( PlainTube => $tube2 );

The constructor takes quite a few arguments, all of which are optional
with sensible defaults. Returns a plugin object suitable for feeding to L<POE::Component::IRC>'s C<plugin_add()> method.

=head2 DEFAULT BEHAVIOUR

When no aguments are specified the plugin will behave in the following way:

=over 5

=item *

Watch for YouTube links in any channel we are joined in presented by anyone.
The messages must be prefixed with the trigger, i.e. must match 
C<qr/^youtube\s+/i>

=item *

Resolve the link to .flv file and send C<'youtube_got_uri'> event.

=item *

No downloading will be done at all.

=back

=head2 ARGUMENTS

The constructor takes several arguments which allow customization if
a need arises. This is a short list of accepted arguments and their default
values (if any), the description of each is provided afterwards.
I<All of them are optional>:

    found_uri_event => 'youtube_found_uri',
    got_uri_event   => 'youtube_got_flv_uri',
    store_event     => 'youtube_stored',
    resolve         => 1,
    replace         => qr/\W/ ,
    replace_char    => '_',
    trigger         => qr/^youtube\s+/i,
    root_store      => 1,

Also, there are several arguments which by default do not C<exists()>:

    channels
    banned
    users
    store_users
    auto
    where
    eat

=head3 found_uri_event

    ->new( found_uri_event => 'event_to_send_when_we_see_a_link' );

The event name of the event to send when matching
users in matching channels with matching trigger (if set, see below) send
a URI which resembles YouTube URI. In most cases you probably
wouldn't even want to set up a handler for this one.
Defaults to: C<youtube_found_uri>

=head3 got_uri_event

    ->new( got_uri_event => 'event_to_send_when_flv_is_resolved' );

This argument specifies the event name of the event to send when 
the direct link to C<.flv> is resolved. Defaults to: C<youtube_got_flv_uri>

=head3 store_event

    ->new( store_event => 'event_to_send_when_flv_is_downloaded' );

Specifies the event name of the event to send when C<.flv> file has been
downloaded (provided downloading is enabled, see C<where> option
below). Defaults to:
C<youtube_stored>

=head3 resolve

    ->new( resolve => 0 );

Setting this argument to a false value will disable resolving of direct
links to C<.flv> files. Plugin will be only sending events when matching
users in matching channels with matching trigger send
a URI which resembles YouTube URI. Defaults to: C<1>

=head3 replace

    ->new( replace => qr/\W/, replace_char => '_' );
    
    ->new(
        replace      => [ qr/-/, qr/\W/ ],
        replace_char => [ '_',   '.'    ],
    );

When C<.flv> downloading is turned on, the title of the movie will be
used as the filename (with C<.flv> extension appended). The C<replace>
argument may be either a regex, or an arrayref of regexes. The matching
characters will be replaced with whatever you set in the C<replace_char>
option (see below). When argument is an arrayref, the argument to
C<replace_char> must also be an arrayref as each matching regex will
be replaced with corresponding element from the C<replace_char> arrayref.
Defaults to: C<qr/\W/>

=head3 replace_char

    ->new( replace => qr/\W/, replace_char => '_' );
    
    ->new(
        replace      => [ qr/-/, qr/\W/ ],
        replace_char => [ '_',   '.'    ],
    );

See description of C<replace> option above. Value may be either a regex
or an arrayref of regexes. Defaults to underscore character: C<_>

=head3 trigger

    ->new( trigger => qr/^ (?:you)? tube\s+/i );

If the line posted in the channel matches the regex, which is the value of
the C<trigger> argument, the plugin will scan it for any YouTube links
and act approprietely on them (such as resolving C<.flv>, etc). Note: when 
C<auto> option (see below) is set, C<trigger> has no effect. Defaults to:
C<qr/^youtube\s+/i>

=head3 root_store

    ->new( root_store => 0 );

Specifies whether or not downloading of movies should be done when the link
was posted by the user who doesn't match the regex of C<store_users> option
(see below), (if
downloading is turned on, see C<where> option below). Defaults to: C<1>

=head3 channels

    ->new( channels => [ '#tubes', '#moar_tubes' ] );

Specifies the channels on which the plugin is active. Argument must be
an arrayref. By default plugin is active on all joined channels.

=head3 banned

    ->new( banned => qr/Evil!spammer@spam.net/ );

Takes a regex as a value. Plugin will ignore any user masks matching
the regex. By default no bans are set.

=head3 users

    ->new( users => qr/Only!me@home.net | my!friend@neighbour.net/x );

Takes a regex as a value. If set, plugin will listen only to users with
masks matching this regex. By default plugin listens to all users.

=head3 store_users

    ->new( store_users => qr/Only!me@home.net | my!friend@neighbour.net/x );

Takes a regex as a value. If downloading of movies is turned on (see
C<where> option below) the users with masks matching this regex will
trigger the download of the movie. Unless you have a really large hard
drive you'd probably want to only specify trusted people in here. Note:
if C<root_store> option (see above) is set to a false value, C<store_users>
will not have any effect and everybody will trigger downloading. By default
C<store_users> does not C<exists()> and C<root_store> option is set to
a true value, effectively disabling the download option for everyone. Note:
you'll need to set the C<where> option (see below) to enable any downloading.

=head3 auto

    ->new( auto => 1 )

Takes true and false values. When set to a true value, the plugin will
parse every line of input for YouTube URIs, effectively disabling the
C<trigger> option (see above). By default C<auto> does not exists() and only
lines matching C<trigger> will be scanned for YouTube URIs.

=head3 where

    ->new( where => '/home/zoffix/tube_movies/' );

This is the key argument to enable downloading of movies. It takes a scalar
as an argument specifying the path of the directory to store the movies in.
Unless it's set, no downloading will be performed irrelevant of values of
C<root_store> and C<store_users> options. By default C<where> doesn't
C<exists()>, thus plugin doesn't download anything at all.

=head3 eat

    ->new( eat => 1 );

If you are familiar with L<POE::Component::IRC::Plugin>, setting C<eat> to
a true value will return C<PCI_EAT_ALL> from component's public message event handler, otherwise it will return C<PCI_EAT_NONE>. For the rest of
you, this means this if you set C<eat> to a true value, plugin will "eat"
the public events if they contain YouTube URIs, thus anything listening to
the events after the plugin won't get them. Refer to
L<POE::Component::IRC::Plugin> documentation for more information.
By default C<eat> does not C<exists()> (i.e. plugin returns C<PCI_EAT_NONE>).

=head1 OUTPUT

The events which you have registered with C<found_uri_event>, C<got_uri_event> and C<store_event>, which by default are C<youtube_found_uri>, C<youtube_got_flv_uri> and C<youtube_stored>
respectively, will recieve output in C<ARG0>.

=head2 found_uri_event

    $VAR1 = {
          'what' => 'youtube http://www.youtube.com/watch?v=KVMGdFa90iw',
          'who' => 'Zoffix!n=Zoffix@unaffiliated/zoffix',
          'channel' => '#zofbot',
          'links' => [
                       'http://www.youtube.com/watch?v=KVMGdFa90iw'
                     ]
        };

This event will be sent whenever plugin spots YouTube URIs in the channel,
(providing the requirements are met, see C<channels>, C<auto>, C<trigger>
and the rest of option in the contructor). C<ARG0> will be a hashref with
four keys:

=head3 what

    { 'what' => 'youtube http://www.youtube.com/watch?v=KVMGdFa90iw' }

The C<what> key will contain the text of the message sent by the user
which contained YouTube URI.

=head3 who

    { 'who' => 'Zoffix!n=Zoffix@unaffiliated/zoffix' }

The C<who> key will contain the mask of the user who sent the message with
YouTube URI.

=head3 channel

    { 'channel' => '#zofbot' }

The C<channel> key will contain the channel where the message with YouTube
URI appeared.

=head3 links

    {
        'links' => [
                'http://www.youtube.com/watch?v=KVMGdFa90iw'
        ]
    }

The C<links> key will contain an arrayref with YouTube links spotted in the
message. The reason it is an arrayref is because one message may contain
several URIs.

=head2 got_uri_event

    $VAR1 = {
          'out' => 'http://www.youtube.com/get_video.php?video_id=KVMGdFa90iw&t=OEgsToPDskKPgFOUMl4o_AN7jGxiOK-c',
          '_data' => {
                       'what' => 'youtube http://www.youtube.com/watch?v=KVMGdFa90iw',
                       'who' => 'Zoffix!n=Zoffix@unaffiliated/zoffix',
                       'channel' => '#zofbot'
                     },
          'title' => 'Julie Louise Gerberding, MD answers the Davos question',
          'uri' => 'http://www.youtube.com/watch?v=KVMGdFa90iw'
        };

This event will be sent when plugin successfully resolves a C<.flv> URI.
C<ARG0> will contain a hashref with the following keys:

=head3 out

    {  'out' => 'http://www.youtube.com/get_video.php?video_id=KVMGdFa90iw&t=OEgsToPDskKPgFOUMl4o_AN7jGxiOK-c' }

The C<out> key will contain the URI to the C<.flv> file (yes it won't
actually have a C<.flv> extension).

=head3 title

    { 'title' => 'Julie Louise Gerberding, MD answers the Davos question' }

The C<title> key will contain the title of the movie.

=head3 uri

    { 'uri' => 'http://www.youtube.com/watch?v=KVMGdFa90iw' }

The C<uri> key will contain the original YouTube URI of the page with the
movie.

=head3 _data

    {
        '_data' => {
                'what' => 'youtube http://www.youtube.com/watch?v=KVMGdFa90iw',
                'who' => 'Zoffix!n=Zoffix@unaffiliated/zoffix',
                'channel' => '#zofbot'
                },
    }

The C<_data> key will contain the data of where we got the URI from. This
is basically the C<ARG0> from C<found_uri_event> (see above) without the
C<links> key.

=head3 error

If an error occured while resolving C<.flv> URI, C<error> key will contain
the reason... with garbage from C<croak()> appended (don't blame me for that, see L<WWW::YouTube::VideoLink>)

=head2 store_event

    $VAR1 = {
          'flv_uri' => 'http://www.youtube.com/get_video.php?video_id=KVMGdFa90iw&t=OEgsToPDskKPgFOUMl4o_AN7jGxiOK-c',
          '_data' => {
                       'what' => 'youtube http://www.youtube.com/watch?v=KVMGdFa90iw',
                       'who' => 'Zoffix!n=Zoffix@unaffiliated/zoffix',
                       'channel' => '#zofbot'
                     },
          'response' => bless( { blah blah }, 'HTTP::Response' ),
          'title' => 'Julie Louise Gerberding, MD answers the Davos question',
          'where' => '/tmp/Julie-Louise-Gerberding_-MD-answers-the-Davos-question.flv'
        };

This event will be sent after the download of C<.flv> file is completed
(if such functionality is enabled of course). The C<ARG0> will contain
a hashref with the following keys:

=head3 flv_uri

    { 'flv_uri' => 'http://www.youtube.com/get_video.php?video_id=KVMGdFa90iw&t=OEgsToPDskKPgFOUMl4o_AN7jGxiOK-c' }

The key C<flv_uri> will contain the URI of the C<.flv> file that we downloaded.

=head3 _data

    {
          '_data' => {
                       'what' => 'youtube http://www.youtube.com/watch?v=KVMGdFa90iw',
                       'who' => 'Zoffix!n=Zoffix@unaffiliated/zoffix',
                       'channel' => '#zofbot'
                     },
    }

The C<_data> key will contain the information about where we got the
YouTube link from. It's identical to the C<_data> key from the 
C<got_uri_event> event (see above).

=head3 response

    { 'response' => bless( { blah blah }, 'HTTP::Response' ), }

In case you'd want to inspect it. The C<response> key will contain the
L<HTTP::Response> object, which was obtained when we were downloading
the movie. 

=head3 title

    { 'title' => 'Julie Louise Gerberding, MD answers the Davos question' }

The C<title> key will contain the title of the movie.

=head3 where

    { 'where' => '/tmp/Julie-Louise-Gerberding_-MD-answers-the-Davos-question.flv' }

The C<where> key will contain the path to the movie file.

=head3 store_error

    { 'store_error' => '304 Not Modified' }

In case of an error, C<store_erro> key will be present and will contain
the explanation of why we failed.

=head1 SEE ALSO

L<POE::Component::IRC>, L<POE::Component::IRC::Plugin>,
L<POE::Component::WWW::YouTube::VideoURI>

=head1 AUTHOR

Zoffix Znet, C<< <zoffix at cpan.org> >>
(L<http://zoffix.com>, L<http://haslayout.net>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-poe-component-irc-plugin-youtube-moviefindstore at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=POE-Component-IRC-Plugin-YouTube-MovieFindStore>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc POE::Component::IRC::Plugin::YouTube::MovieFindStore

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-IRC-Plugin-YouTube-MovieFindStore>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/POE-Component-IRC-Plugin-YouTube-MovieFindStore>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/POE-Component-IRC-Plugin-YouTube-MovieFindStore>

=item * Search CPAN

L<http://search.cpan.org/dist/POE-Component-IRC-Plugin-YouTube-MovieFindStore>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 Zoffix Znet, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
