package System::Command;

use warnings;
use strict;
use 5.006;

use Carp;
use Cwd qw( cwd );
use IO::Handle;
use IPC::Open3 qw( open3 );
use List::Util qw( reduce );

our $VERSION = '1.00';

# a few simple accessors
for my $attr (qw( pid stdin stdout stderr exit signal core )) {
    no strict 'refs';
    *$attr = sub { return $_[0]{$attr} };
}
for my $attr (qw( cmdline )) {
    no strict 'refs';
    *$attr = sub { return @{ $_[0]{$attr} } };
}

sub new {
    my ( $class, @cmd ) = @_;

    # split the args
    my @o;
    @cmd = grep { !( ref eq 'HASH' ? push @o, $_ : 0 ) } @cmd;

    # merge the option hashes
    my $o = reduce {
        {
            %$a, %$b,
                exists $a->{env} && exists $b->{env}
                ? ( env => { %{ $a->{env} }, %{ $b->{env} } } )
                : ()
        };
    }
    @o;

    # chdir to the expected directory
    my $orig = cwd;
    my $dest = defined $o->{cwd} ? $o->{cwd} : undef;
    if ( defined $dest ) {
        chdir $dest or croak "Can't chdir to $dest: $!";
    }

    # keep changes to the environment local
    local %ENV = %ENV;

    # update the environment
    @ENV{ keys %{ $o->{env} } } = values %{ $o->{env} }
        if exists $o->{env};

    # start the command
    my ( $in, $out, $err );
    $err = Symbol::gensym;
    my $pid = eval { open3( $in, $out, $err, @cmd ); };

    # FIXME - better check open3 error conditions
    croak $@ if !defined $pid;

    # some input was provided
    if ( defined $o->{input} ) {
        local $SIG{PIPE}
            = sub { croak "Broken pipe when writing to: @cmd" };
        print {$in} $o->{input} if length $o->{input};
        $in->close;
    }

    # chdir back to origin
    if ( defined $dest ) {
        chdir $orig or croak "Can't chdir back to $orig: $!";
    }

    # create the object
    return bless {
        cmdline => [ @cmd ],
        pid     => $pid,
        stdin   => $in,
        stdout  => $out,
        stderr  => $err,
    }, $class;
}

sub close {
    my ($self) = @_;

    # close all pipes
    my ( $in, $out, $err ) = @{$self}{qw( stdin stdout stderr )};
    $in->opened  and $in->close  || carp "error closing stdin: $!";
    $out->opened and $out->close || carp "error closing stdout: $!";
    $err->opened and $err->close || carp "error closing stderr: $!";

    # and wait for the child
    waitpid $self->{pid}, 0;

    # check $?
    @{$self}{qw( exit signal core )} = ( $? >> 8, $? & 127, $? & 128 );

    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->close if !exists $self->{exit};
}

1;

__END__


    use System::Command;

    my $foo = System::Command->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

=head1 AUTHOR

Philippe Bruhat (BooK), C<< <book at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-system-command at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=System-Command>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc System::Command


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=System-Command>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/System-Command>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/System-Command>

=item * Search CPAN

L<http://search.cpan.org/dist/System-Command/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Philippe Bruhat (BooK).

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of System::Command
