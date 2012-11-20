use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'System::Command',
    AUTHOR              => q{Philippe Bruhat (BooK) <book@cpan.org>},
    VERSION_FROM        => 'lib/System/Command.pm',
    ABSTRACT_FROM       => 'lib/System/Command.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'IPC::Open3' => 0,
        'Carp'       => 0,
        'Cwd'        => 0,
        'IO::Handle' => 0,
        'List::Util' => 0,
        'Config'     => 0,
        'POSIX'      => 0,
        'Symbol'     => 0,
    },
    META_MERGE => {
        resources => {
            repository => 'http://github.com/book/System-Command',
        },
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'System-Command-*' },
);
