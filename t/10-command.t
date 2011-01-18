use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw( tempdir );
use Cwd qw( cwd abs_path );
use System::Command;
use constant MSWin32 => $^O eq 'MSWin32';

my $dir   = abs_path( tempdir( CLEANUP => 1 ) );
my $cwd   = cwd;
my $name  = File::Spec->catfile( t => 'info.pl' );
my @tests = (
    {   cmdline => [ $^X, $name ],
        options => {},
    },
    {   cmdline => [
            $^X, $name, { env => { SYSTEM_COMMAND => 'System::Command' } }
        ],
        options => { env => { SYSTEM_COMMAND => 'System::Command' } },
    },
    {   cmdline => [
            $^X, $name,
            { env  => { SYSTEM_COMMAND => 'System::Command' } },
            { },
        ],
        options => {
            env  => { SYSTEM_COMMAND => 'System::Command' },
        },
    },
    {   cmdline => [
            $^X,
            File::Spec->catfile( $cwd => $name ),
            { cwd => $dir, name => 'powie' },
            { env => { SYSTEM_COMMAND => 'System::Command' } },
        ],
        cwd     => $dir,
        name    => File::Spec->catfile( $cwd => $name ),
        options => {
            name => 'powie',
            env  => { SYSTEM_COMMAND => 'System::Command' },
            cwd  => $dir,
        },
    },
    {   cmdline => [
            $^X, $name,
            { env => { SYSTEM_COMMAND => 'System::Command' } },
            { env => { OTHER_ENV      => 'something else' } },
        ],
        options => {
            env => {
                OTHER_ENV      => 'something else',
                SYSTEM_COMMAND => 'System::Command',
            }
        },
    },
    {   cmdline => [
            $^X,
            $name,
            { env => { 'SYSTEM_COMMAND_INPUT' => 1 }, input => 'test input' }
        ],
        options =>
            { env => { 'SYSTEM_COMMAND_INPUT' => 1 }, input => 'test input' }
    },
    {   cmdline => [
            $^X, $name,
            { env => { 'SYSTEM_COMMAND_INPUT' => 1 }, input => '' }
        ],
        options => { env => { 'SYSTEM_COMMAND_INPUT' => 1 }, input => '' }
    },
);
my @fail = (
    {   cmdline =>
            [ $^X, $name, { cwd => File::Spec->catdir( $dir, 'nothere' ) } ],
        cwd     => File::Spec->catdir( $dir, 'nothere' ),
        fail    => qr/^Can't chdir to /,
        options => {},
    },
);

plan tests => 14 * @tests + 2 * @fail;

for my $t ( @tests, @fail ) {

    # run the command
    my $cmd = eval { System::Command->new( @{ $t->{cmdline} } ) };
    if ( $t->{fail} ) {
        ok( !$cmd, 'command failed' );
        like( $@, $t->{fail}, '... expected error message' );
        next;
    }

    isa_ok( $cmd, 'System::Command' );

    # test the handles
    for my $handle (qw( stdin stdout stderr )) {
        isa_ok( $cmd->$handle, 'GLOB' );
        if ( $handle eq 'stdin' ) {
            my $opened = !exists $t->{options}{input};
            is( $cmd->$handle->opened, $opened,
                "$handle @{[ !$opened && 'not ']}opened" );
        }
        else {
            ok( $cmd->$handle->opened, "$handle opened" );
        }
    }

    is_deeply( [ $cmd->cmdline ],
        [ grep { !ref } @{ $t->{cmdline} } ], 'cmdline' );
    is_deeply( $cmd->options, $t->{options}, 'options' );

    # get the output
    my $output = join '', $cmd->stdout->getlines();
    my $errput = join '', $cmd->stderr->getlines();
    is( $errput, '', 'no errput' );

    my $info;
    eval $output;
    my $w32env = {};
    $w32env = { PWD => $t->{options}{cwd} }
        if MSWin32 && exists $t->{options}{cwd};
    is_deeply(
        $info,
        {   argv => [],
            cwd  => $t->{options}{cwd} || $cwd,
            env  => { %ENV, %{ $t->{options}{env} || {} }, %$w32env },
            input => $t->{options}{input} || '',
            name  => $t->{name}           || $name,
            pid   => $cmd->pid,
        },
        "perl $name"
    );

    # close and check
    $cmd->close();
    is( $cmd->exit,   0, 'exit 0' );
    is( $cmd->signal, 0, 'no signal received' );
    is( $cmd->core, $t->{core} || 0, 'no core dumped' );
}

