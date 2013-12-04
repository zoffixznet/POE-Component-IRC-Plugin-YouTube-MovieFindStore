#!/usr/bin/env perl

use strict;
use warnings;
use lib '../lib';

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
                youtube_got_flv_uri
                youtube_found_uri
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
                where        => '/tmp',
                replace      => [ qr/\s+/, qr/[^\w-]/ ],
                replace_char => [ '-',     '_'        ],
                root_store   => 0,
            )
    );
    
    $irc->yield( connect => { } );
    undef;
}

sub irc_001 {
    my ( $kernel, $sender ) = @_[ KERNEL, SENDER ];
    $kernel->post( $sender => join => '#zofbot' );
    undef;
}

sub youtube_got_flv_uri {
    my ( $kernel, $input ) = @_[ KERNEL, ARG0 ];
    use Data::Dumper;
    print Dumper( $input );
    my ( $channel, $who ) = @{ $input->{_data} }{ qw( channel who ) };
    my $nick = ( split /!/, $who )[0];

    $poe_kernel->post( $irc => privmsg => $channel =>
        sprintf "%s, Title: %s URI: %s FLV: %s",
            $nick, @$input{ qw( title  uri  out ) }
    );

    undef;
}

sub youtube_stored {
    my ( $kernel, $input ) = @_[ KERNEL, ARG0 ];
        use Data::Dumper;
    print Dumper( $input );
    my ( $channel, $who ) = @{ $input->{_data} }{ qw( channel who ) };
    my $nick = ( split /!/, $who )[0];

    $poe_kernel->post( $irc => privmsg => $channel =>
        "$nick, saved \cB$input->{title}\cB as \cB$input->{where}\cB"
    );
}


sub youtube_found_uri {
    my ( $kernel, $input ) = @_[ KERNEL, ARG0 ];
    use Data::Dumper;
    print Dumper( $input );
}