use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'System::Command',
    license             => 'perl',
    dist_author         => q{Philippe Bruhat (BooK) <book@cpan.org>},
    dist_version_from   => 'lib/System/Command.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires         => {
        'IPC::Open3' => 0,
        'Carp'       => 0,
        'Cwd'        => 0,
        'IO::Handle' => 0,
        'List::Util' => 0,
        'Config'     => 0,
        'POSIX'      => 0,
        'Symbol'     => 0,
    },
    add_to_cleanup      => [ 'System-Command-*' ],
    meta_merge     => {
        resources => {
            repository => 'http://github.com/book/System-Command',
        },
    },
);

$builder->create_build_script();
