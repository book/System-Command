#!perl
use strict;
use warnings;
use Data::Dumper;

print Data::Dumper->Dump(
    [   {   name => $0,
            pid  => $$,
            argv => \@ARGV,
            env  => \%ENV,
        }
    ],
    ['info']
);
