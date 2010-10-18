use strict;
use warnings;
use Test::More;
use File::Spec;
use System::Command;

my $name = File::Spec->catfile( t => 'info.pl' );
my @tests = (
    {   cmdline => [ $^X, $name ],
        options => {},
    },
    {   cmdline => [ $^X, $name, { name => 'zlonk' } ],
        options => { name => 'zlonk' },
    },
    {   cmdline => [
            $^X, $name, { env => { SYSTEM_COMMAND => 'System::Command' } }
        ],
        options => { env => { SYSTEM_COMMAND => 'System::Command' } },
    },
    {   cmdline => [
            $^X, $name,
            { env => { SYSTEM_COMMAND => 'System::Command' } },
            { env => { OTHER_ENV      => 'something else'  } },
        ],
        options => {
            env => {
                SYSTEM_COMMAND => 'System::Command',
                OTHER_ENV      => 'something else',
            }
        },
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
        $info,
        {   argv => [],
            env  => { %ENV, %{ $t->{options}{env} || {} } },
            name => $t->{name} || $name,
            pid  => $cmd->pid,
        },
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

