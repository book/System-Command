package System::Command;

use warnings;
use strict;
use 5.006;

use Carp;
use Cwd qw( cwd );
use IO::Handle;
use IPC::Open3 qw( open3 );
use Symbol ();
use List::Util qw( reduce );

use Config;
use POSIX ":sys_wait_h";
use constant STATUS  => qw( exit signal core );

our $VERSION = '1.09';

our $QUIET = 0;

sub import {
    my ( $class, @args ) = @_;
    my %arg = ( quiet => sub { $QUIET = 1 } );
    for my $arg (@args) {
        $arg =~ s/^-//;    # allow dashed options
        croak "Unknown option '$arg' in 'use System::Command'"
            if !exists $arg{$arg};
        $arg{$arg}->();
    }
}

# a few simple accessors
for my $attr (qw( pid stdin stdout stderr exit signal core options )) {
    no strict 'refs';
    *$attr = sub { return $_[0]{$attr} };
}
for my $attr (qw( cmdline )) {
    no strict 'refs';
    *$attr = sub { return @{ $_[0]{$attr} } };
}

# a private sub-process spawning function
my $_seq   = 0;
my $_spawn = sub {
    my (@cmd) = @_;
    my $pid;
    # setup filehandles
    my $in  = Symbol::gensym;
    my $out = Symbol::gensym;
    my $err = Symbol::gensym;

    # start the command
    $pid = open3( $in, $out, $err, @cmd );

    return ( $pid, $in, $out, $err );
};

# module methods
sub new {
    my ( $class, @cmd ) = @_;

    # split the args
    my @o;
    @cmd = grep { !( ref eq 'HASH' ? push @o, $_ : 0 ) } @cmd;

    # merge the option hashes
    my $o = reduce {
        +{  %$a, %$b,
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
    if ( exists $o->{env} ) {
        @ENV{ keys %{ $o->{env} } } = values %{ $o->{env} };
        delete $ENV{$_}
            for grep { !defined $o->{env}{$_} } keys %{ $o->{env} };
    }

    # start the command
    my ( $pid, $in, $out, $err ) = eval { $_spawn->(@cmd); };

    # FIXME - better check error conditions
    croak $@ if !defined $pid;

    # some input was provided
    if ( defined $o->{input} ) {
        local $SIG{PIPE}
            = sub { croak "Broken pipe when writing to: @cmd" }
            if $Config{sig_name} =~ /\bPIPE\b/;
        print {$in} $o->{input} if length $o->{input};
        $in->close;
    }

    # chdir back to origin
    if ( defined $dest ) {
        chdir $orig or croak "Can't chdir back to $orig: $!";
    }

    # create the object
    my $self = bless {
        cmdline => [ @cmd ],
        options => $o,
        pid     => $pid,
        stdin   => $in,
        stdout  => $out,
        stderr  => $err,
    }, $class;

    return $self;
}

sub spawn {
    my ( $class, @cmd ) = @_;
    return @{ $class->new(@cmd) }{qw( pid stdin stdout stderr )};
}

sub is_terminated {
    my ($self) = @_;
    my $pid = $self->{pid};

    # Zed's dead, baby. Zed's dead.
    return $pid if !kill 0, $pid and exists $self->{exit};

    # If that is a re-animated body, we're gonna have to kill it.
    return $self->_reap(WNOHANG);
}

sub _reap {
    my ( $self, @flags ) = @_;
    my $pid = $self->{pid};

    if ( my $reaped = waitpid( $pid, @flags ) and !exists $self->{exit} ) {
        my $zed = $reaped == $pid;
        carp "Child process already reaped, check for a SIGCHLD handler"
            if !$zed && !$QUIET;

        @{$self}{ STATUS() }
            = $zed
            ? ( $? >> 8, $? & 127, $? & 128 )
            : ( -1, -1, -1 );

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

1;

__END__

=head1 NAME

System::Command - Object for running system commands

=head1 SYNOPSIS

    use System::Command;

    # invoke an external command, and return an object
    $cmd = System::Command->new( @cmd );

    # options can be passed as a hashref
    $cmd = System::Command->new( @cmd, \%option );

    # $cmd is basically a hash, with keys / accessors
    $cmd->stdin();     # filehandle to the process' stdin (write)
    $cmd->stdout();    # filehandle to the process' stdout (read)
    $cmd->stderr();    # filehandle to the process' stdout (read)
    $cmd->pid();       # pid of the child process

    # find out if the child process died
    if ( $cmd->is_terminated() ) {
        # the handles are not closed yet
        # but $cmd->exit() et al. are available
    }

    # done!
    $cmd->close();

    # exit information
    $cmd->exit();      # exit status
    $cmd->signal();    # signal
    $cmd->core();      # core dumped? (boolean)

    # cut to the chase
    my ( $pid, $in, $out, $err ) = System::Command->spawn(@cmd);

=head1 DESCRIPTION

C<System::Command> is a class that launches external system commands
and return an object representing them, allowing to interact with them
through their C<STDIN>, C<STDOUT> and C<STDERR> handles.

=head1 METHODS

C<System::Command> supports the following methods:

=head2 new( @cmd )

Runs an external command using the list in C<@cmd>.

If C<@cmd> contains a hash reference, it is taken as an I<option> hash.

If several option hashes are passed to C<new()>, they will be merged
together with individual values being overridden by those (with the same
key) from hashes that appear later in the list.

To allow subclasses to support their own set of options, unrecognized
options are silently ignored.

The recognized keys are:

=over 4

=item C<cwd>

The I<current working directory> in which the command will be run.

=item C<env>

A hashref containing key / values to add to the command environment.

If a value is C<undef>, the variable corresponding to the key will
be I<removed> from the environment.

=item C<input>

A string that is send to the command's standard input, which is then closed.

Using the empty string as C<input> will close the command's standard input
without writing to it.

Using C<undef> as C<input> will not do anything. This behaviour provides
a way to modify previous options populated by some other part of the program.

On some systems, some commands may close standard input on startup,
which will cause a SIGPIPE when trying to write to it. This will raise
an exception.

=back

The C<System::Command> object returned by C<new()> has a number of
attributes defined (see below).


=head2 close()

Close all pipes to the child process, collects exit status, etc.
and defines a number of attributes (see below).

=head2 is_terminated()

Returns a true value if the underlying process was terminated.

If the process was indeed terminated, collects exit status, etc.
and defines the same attributes as C<close()>, but does B<not> close
all pipes to the child process,


=head2 spawn( @cmd )

This shortcut method calls C<new()> (and so accepts options in the same
manner) and directly returns the C<pid>, C<stdin>, C<stdout> and C<stderr>
attributes, in that order.


=head2 Accessors

The attributes of a C<System::Command> object are also accessible
through a number of accessors.

The object returned by C<new()> will have the following attributes defined:

=over 4

=item cmdline()

Return the command-line actually executed, as a list of strings.

=item options()

The merged list of options used to run the command.

=item pid()

The PID of the underlying command.

=item stdin()

A filehandle opened in write mode to the child process' standard input.

=item stdout()

A filehandle opened in read mode to the child process' standard output.

=item stderr()

A filehandle opened in read mode to the child process' standard error output.

=back

Regarding the handles to the child process, note that in the following code:

    my $fh = System::Command->new( @cmd )->stdout;

C<$fh> is opened and points to the output handle of the child process,
while the anonymous C<System::Command> object has been destroyed. Once
C<$fh> is destroyed, the subprocess will be reaped, thus avoiding zombies.


After the call to C<close()> or after C<is_terminated()> returns true,
the following attributes will be defined:

=over 4

=item exit()

The exit status of the underlying command.

=item core()

A boolean value indicating if the command dumped core.

=item signal()

The signal, if any, that killed the command.

=back

=head1 CAVEAT EMPTOR

Note that C<System::Command> uses C<waitpid()> to catch the status
information of the child processes it starts. This means that if your
code (or any module you C<use>) does something like the following:

    local $SIG{CHLD} = 'IGNORE';    # reap child processes

C<System::Command> will not be able to capture the C<exit>, C<core>
and C<signal> attributes. It will instead set all of them to the
impossible value C<-1>, and display the warning
C<Child process already reaped, check for a SIGCHLD handler>.

To silence this warning (and accept the impossible status information),
load C<System::Command> with:

    use System::Command -quiet;

It is also possible to more finely control the warning by setting
the C<$System::Command::QUIET> variable (the warning is not emitted
if the variable is set to a true value).

If the subprocess started by C<System::Command> has a short life
expectancy, and no other child process is expected to die during that
time, you could even disable the handler locally (use at your own risks):

    {
        local $SIG{CHLD};
        my $cmd = System::Command->new(@cmd);
        ...
    }

=head1 AUTHOR

Philippe Bruhat (BooK), C<< <book at cpan.org> >>

=head1 ACKNOWLEDGEMENTS

Thanks to Alexis Sukrieh who, when he saw the description of
C<Git::Repository::Command> during my talk at OSDC.fr 2010, asked
why it was not an independent module. This module was started by
taking out of C<Git::Repository::Command> 1.08 the parts that
weren't related to Git.


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


=head1 COPYRIGHT

Copyright 2010-2011 Philippe Bruhat (BooK).

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

