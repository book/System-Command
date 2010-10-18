#!perl
use strict;
use warnings;
use Cwd qw( cwd );
use Data::Dumper;

print Data::Dumper->Dump(
    [   {   name => $0,
            pid  => $$,
            argv => \@ARGV,
            env  => \%ENV,
            cwd  => cwd(),
        }
    ],
    ['info']
);
