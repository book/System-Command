use strict;
use warnings;
use Test::More;
use File::Spec;
use System::Command;

my $name = File::Spec->catfile( t => 'info.pl' );
my @tests = (
    {   cmdline => [ $^X, $name ],
        name    => $name,
        options => {},
    },
);

plan tests => 13 * @tests;

for my $t (@tests) {

    # run the command
    my $cmd = System::Command->new( @{ $t->{cmdline} } );
    isa_ok( $cmd, 'System::Command' );

    # test the handles
    for my $handle (qw( stdin stdout stderr )) {
        isa_ok( $cmd->$handle, 'GLOB' );
        ok( $cmd->$handle->opened, "$handle opened" );
    }

    is_deeply( [ $cmd->cmdline ],
        [ grep { !ref } @{ $t->{cmdline} } ], 'cmdline' );
    is_deeply( $cmd->options, $t->{options}, 'options' );

    # get the output
    my $output = join '', $cmd->stdout->getlines();
    my $info;
    eval $output;

    is_deeply(
        {   pid  => $cmd->pid,
            argv => [],
            name => $name,
            env  => { %ENV, %{ $t->{options}{env} || {} } },
        },
        $info,
        "perl $name"
    );

    # close and check
    $cmd->close();
    is( $cmd->exit,   0, 'exit 0' );
    is( $cmd->signal, 0, 'no signal received' );
    is( $cmd->core, $t->{core} || 0, 'no core dumped' );
}

# TODO
# - test with options (cwd, input, env)
# - test with "native" programs (not "$^X info.pl")
# - test with multiple option hashes
# - test with full path

