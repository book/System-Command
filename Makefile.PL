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
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'System-Command-*' },
);
