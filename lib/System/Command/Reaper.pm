package System::Command::Reaper;

use strict;
use warnings;
use 5.006;

use Carp;
use Scalar::Util qw( weaken );

use constant HANDLES => qw( stdin stdout stderr );
use constant STATUS  => qw( exit signal core );

our $VERSION = '1.01';

sub new {
    my ($class, $command) = @_;
    my $self = bless { command => $command }, $class;

    # copy/weaken the important keys
    @{$self}{ pid => HANDLES } = @{$command}{ pid => HANDLES };
    weaken $self->{$_} for ( command => HANDLES );

    return $self;
}

sub reap {
    my ($self) = @_;

    # close all pipes
    my ( $in, $out, $err ) = @{$self}{qw( stdin stdout stderr )};
    $in  and $in->opened  and $in->close  || carp "error closing stdin: $!";
    $out and $out->opened and $out->close || carp "error closing stdout: $!";
    $err and $err->opened and $err->close || carp "error closing stderr: $!";

    # and wait for the child (if any)
    if ( my $reaped = waitpid( $self->{pid}, 0 ) and !exists $self->{exit} ) {
        my $zed = $reaped == $self->{pid};
        carp "Child process already reaped, check for a SIGCHLD handler"
            if !$zed && !$System::Command::QUIET;

        # check $?
        @{$self}{ STATUS() }
            = $zed
            ? ( $? >> 8, $? & 127, $? & 128 )
            : ( -1, -1, -1 );

        # does our creator still exist?
        @{ $self->{command} }{ STATUS() } = @{$self}{ STATUS() }
            if defined $self->{command};
    }

    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->reap if !exists $self->{exit};
}

1;

__END__

=head1 NAME

System::Command::Reaper - Reap processes started by System::Command

=head1 SYNOPSIS

This class is used for internal purposes.
Move along, nothing to see here.

=head1 DESCRIPTION

The C<System::Command> objects delegate the reaping of child
processes to C<System::Command::Reaper> objects. This allows a user
to create a C<System::Command> and discard it after having obtained
one or more references to its handles connected to the child process.

The typical use case looks like this:

    my $fh = System::Command->new( @cmd )->stdout();

The child process is reaped either through a direct call to C<close()>
or when the command object and all its handles have been destroyed,
thus avoiding zombies (which would be reaped by the system at the end
of the main program).

This is possible thanks to the following reference graph:

        System::Command
         |   |   |  ^|
         v   v   v  !|
        in out err  !|
        ^|  ^|  ^|  !|
        !v  !v  !v  !v
    System::Command::Reaper

Legend:
    | normal ref
    ! weak ref

The C<System::Command::Reaper> object acts as a sentinel, that takes
care of reaping the child process when the original C<System::Command>
and its filehandles have been destroyed (or when C<System::Command>
C<close()> method is being called).

=head1 METHODS

C<System::Command::Reaper> supports the following methods:

=head2 new( $command )

Create a new C<System::Command::Reaper> object attached to the
C<System::Command> object passed as a parameter.

=head2 reap()

Close all the opened filehandles of the main C<System::Command> object,
reaps the child process, and updates the main object with the status
information of the child process.

C<DESTROY> calls C<reap()> when the sentinel is being destroyed.

=head1 AUTHOR

Philippe Bruhat (BooK), C<< <book at cpan.org> >>

=head1 ACKNOWLEDGEMENTS

This scheme owes a lot to Vincent Pit who on #perlfr provided the
general idea (use a proxy to delay object destruction and child process
reaping) with code examples, which I then adapted to my needs.


=head1 COPYRIGHT

Copyright 2010-2011 Philippe Bruhat (BooK), all rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

