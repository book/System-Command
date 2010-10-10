#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'System::Command' ) || print "Bail out!
";
}

diag( "Testing System::Command $System::Command::VERSION, Perl $], $^X" );
