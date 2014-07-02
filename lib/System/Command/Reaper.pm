package System::Command::Reaper;

use strict;
use warnings;
use 5.006;

use Carp;
use Scalar::Util qw( weaken );

use POSIX ":sys_wait_h";

use constant MSWin32 => $^O eq 'MSWin32';
use constant HANDLES => qw( stdin stdout stderr );
use constant STATUS  => qw( exit signal core );

sub new {
    my ($class, $command) = @_;
    my $self = bless { command => $command }, $class;

    # copy/weaken the important keys
    @{$self}{ pid => HANDLES } = @{$command}{ pid => HANDLES };
    weaken $self->{$_} for ( command => HANDLES );

    return $self;
}

# this is necessary, because kill(0,pid) is misimplemented in perl core
my $_is_alive = MSWin32
    ? sub { return `tasklist /FO CSV /NH /fi "PID eq $_[0]"` =~ /^"/ }
    : sub { return kill 0, $_[0]; };

sub is_terminated {
    my ($self) = @_;
    my $pid = $self->{pid};

    # Zed's dead, baby. Zed's dead.
    return $pid if !$_is_alive->($pid) and exists $self->{exit};

    # If that is a re-animated body, we're gonna have to kill it.
    return $self->_reap(WNOHANG);
}

sub _reap {
    my ( $self, $flags ) = @_;

    $flags = 0 if ! defined $flags;

    my $pid = $self->{pid};

    # REPENT/THE END IS/EXTREMELY/FUCKING/NIGH
    if ( my $reaped = waitpid( $pid, $flags ) and !exists $self->{exit} ) {
        my $zed = $reaped == $pid;
        carp "Child process already reaped, check for a SIGCHLD handler"
            if !$zed && !$System::Command::QUIET && !MSWin32;

        # What do you think? "Zombie Kill of the Week"?
        @{$self}{ STATUS() }
            = $zed
            ? ( $? >> 8, $? & 127, $? & 128 )
            : ( -1, -1, -1 );

        # Who died and made you fucking king of the zombies?
        @{ $self->{command} }{ STATUS() } = @{$self}{ STATUS() }
            if defined $self->{command};

        return $reaped;    # It's dead, Jim!
    }

    # Look! It's moving. It's alive. It's alive...
    return;
}

sub close {
    my ($self) = @_;

    # close all pipes
    my ( $in, $out, $err ) = @{$self}{qw( stdin stdout stderr )};
    $in  and $in->opened  and $in->close  || carp "error closing stdin: $!";
    $out and $out->opened and $out->close || carp "error closing stdout: $!";
    $err and $err->opened and $err->close || carp "error closing stderr: $!";

    # and wait for the child (if any)
    $self->_reap();

    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->close if !exists $self->{exit};
}

1;

__END__

# ABSTRACT: Reap processes started by System::Command

=head1 SYNOPSIS

This class is used for internal purposes.
Move along, nothing to see here.

=head1 DESCRIPTION

The L<System::Command> objects delegate the reaping of child
processes to System::Command::Reaper objects. This allows a user
to create a L<System::Command> and discard it after having obtained
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

The System::Command::Reaper object acts as a sentinel, that takes
care of reaping the child process when the original L<System::Command>
and its filehandles have been destroyed (or when L<System::Command>
C<close()> method is being called).

=head1 METHODS

System::Command::Reaper supports the following methods:

=head2 new

    my $reaper = System::Command::Reaper->new( $cmd );

Create a new System::Command::Reaper object attached to the
L<System::Command> object passed as a parameter.

=head2 close

    $reaper->close();

Close all the opened filehandles of the main L<System::Command> object,
reaps the child process, and updates the main object with the status
information of the child process.

C<DESTROY> calls C<close()> when the sentinel is being destroyed.

=head2 is_terminated

    if ( $reaper->is_terminated ) {...}

Returns a true value if the underlying process was terminated.

If the process was indeed terminated, collects exit status, etc.

=head1 AUTHOR

Philippe Bruhat (BooK), C<< <book at cpan.org> >>

=head1 ACKNOWLEDGEMENTS

This scheme owes a lot to Vincent Pit who on #perlfr provided the
general idea (use a proxy to delay object destruction and child process
reaping) with code examples, which I then adapted to my needs.

=head1 COPYRIGHT

Copyright 2010-2013 Philippe Bruhat (BooK), all rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
