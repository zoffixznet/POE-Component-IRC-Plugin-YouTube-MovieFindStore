#!/usr/bin/env perl

use Test::More tests => 6;

BEGIN {
    use_ok('File::Spec');
    use_ok('POE');
    use_ok('POE::Component::IRC');
    use_ok('POE::Component::IRC::Plugin');
    use_ok('POE::Component::WWW::YouTube::VideoURI');
	use_ok( 'POE::Component::IRC::Plugin::YouTube::MovieFindStore' );
}

diag( "Testing POE::Component::IRC::Plugin::YouTube::MovieFindStore $POE::Component::IRC::Plugin::YouTube::MovieFindStore::VERSION, Perl $], $^X" );
