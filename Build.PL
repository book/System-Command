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
    add_to_cleanup      => [ 'System-Command-*' ],
);

$builder->create_build_script();
