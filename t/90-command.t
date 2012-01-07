use warnings;
use strict;
use Test::More;

BEGIN {
    plan skip_all => 'Test::Command not available'
        if ! eval 'use Test::Command; 1;';
}

use System::Command;

plan tests => 2;

stdout_like(q{perl -le 'print STDOUT "STDOUT\n"'}, qr/STDOUT/, 'STDOUT');
stderr_like(q{perl -le 'print STDERR "STDERR\n"'}, qr/STDERR/, 'STDERR');

