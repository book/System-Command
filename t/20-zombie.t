use strict;
use warnings;
use Test::More;
use System::Command;
use File::Spec;

my @cmd = ( $^X, File::Spec->catfile( t => 'fail.pl' ) );

plan tests => 10;

my $status = 1;
my $delay  = 2;

# just started the command
my $cmd = System::Command->new( @cmd, $status, $delay );
ok( !$cmd->is_terminated, 'child still alive' );
is( $cmd->exit, undef, 'no exit status' );

# leave it time to die
sleep $delay + 1;
ok( $cmd->is_terminated, 'child is dead now' );
is( $cmd->exit, $status, 'exit status collected' );

# yes, our handles are still open
ok( $cmd->is_terminated,  'child is still dead' );
ok( $cmd->stdout->opened, 'stdout still opened' );
ok( $cmd->stderr->opened, 'stderr still opened' );

# close our handles now
$cmd->close;
ok( $cmd->is_terminated,   'child is still dead' );
ok( !$cmd->stdout->opened, 'stdout closed' );
ok( !$cmd->stderr->opened, 'stderr closed' );

# don't confuse Test::More
$? = 0;
