use warnings;
use strict;
use Test::More;

BEGIN {
    plan skip_all => 'Test::Output not available'
        if ! eval 'use Test::Output; 1;';
}

use System::Command;

sub print_implicit { print "STDOUT\n"; }
sub print_stdout   { print STDOUT "STDOUT\n"; }
sub print_stderr   { print STDERR "STDERR\n"; }

plan tests => 10;

# before
stdout_is( \&print_implicit, "STDOUT\n", 'print' );
stdout_is( \&print_stdout,   "STDOUT\n", 'print STDOUT' );
stderr_is( \&print_stderr, "STDERR\n", 'print STDERR' );

# during
{
    my $cmd = System::Command->new( $^X => qw( -le print+1 ) );
    stdout_is( \&print_implicit, "STDOUT\n", 'print' );
    stdout_is( \&print_stdout,   "STDOUT\n", 'print STDOUT' );
    stderr_is( \&print_stderr, "STDERR\n", 'print STDERR' );

    is( $cmd->stdout->getline, "1\n", 'expected command output' );
    $cmd->close;
}

# after
stdout_is( \&print_implicit, "STDOUT\n", 'print' );
stdout_is( \&print_stdout,   "STDOUT\n", 'print STDOUT' );
stderr_is( \&print_stderr, "STDERR\n", 'print STDERR' );

