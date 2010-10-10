use strict;
use warnings;
use Test::More;
use File::Spec;
use System::Command;

plan 'no_plan';

# run a single command
my $name = File::Spec->catfile( t => 'info.pl' );
my $cmd = System::Command->new( $^X, $name );
isa_ok( $cmd, 'System::Command' );

# test the handles
for my $handle (qw( stdin stdout stderr )) {
    isa_ok( $cmd->$handle, 'GLOB' );
    ok( $cmd->$handle->opened, "$handle opened" );
}

is_deeply( [ $cmd->cmdline ], [ $^X, $name ], 'cmdline' );

# get the output
my $output = join '', $cmd->stdout->getlines();
my $info;
eval $output;

is_deeply( { pid => $cmd->pid, argv => [], name => $name },
    $info, "perl $name" );

# close and check
$cmd->close();
is( $cmd->exit,   0, 'exit 0' );
is( $cmd->signal, 0, 'no signal received' );
is( $cmd->core,   0, 'no core dumped' );

# TODO
# - test with options (cwd, input, env)
# - test with "native" programs (not "$^X info.pl")
# - test with multiple option hashes
# - test with full path

