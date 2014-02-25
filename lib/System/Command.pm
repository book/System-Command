package System::Command;

use warnings;
use strict;
use 5.006;

use Carp;
use Cwd qw( cwd );
use IO::Handle;
use Symbol ();
use Scalar::Util qw( blessed );
use List::Util qw( reduce );
use System::Command::Reaper;

use Config;
use Fcntl qw( F_GETFD F_SETFD FD_CLOEXEC );

# MSWin32 support
use constant MSWin32 => $^O eq 'MSWin32';
require IPC::Run if MSWin32;

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

# REALLY PRIVATE FUNCTIONS
# a sub-process spawning function
my $_spawn = sub {
    my (@cmd) = @_;
    my $pid;

    # setup filehandles
    my $in  = Symbol::gensym;
    my $out = Symbol::gensym;
    my $err = Symbol::gensym;

    # no buffering on pipes used for writing
    select( ( select($in), $| = 1 )[0] );

    # start the command
    if (MSWin32) {
        $pid = IPC::Run::start(
            [@cmd],
            '<pipe'  => $in,
            '>pipe'  => $out,
            '2>pipe' => $err,
        );
    }
    else {

        # the code below takes inspiration from IPC::Open3 and Sys::Cmd

        # create handles for the child process (using CAPITALS)
        my $IN  = Symbol::gensym;
        my $OUT = Symbol::gensym;
        my $ERR = Symbol::gensym;

        # no buffering on pipes used for writing
        select( ( select($OUT), $| = 1 )[0] );
        select( ( select($ERR), $| = 1 )[0] );

        # connect parent and child with pipes
        pipe $IN,  $in  or croak "input pipe(): $!";
        pipe $out, $OUT or croak "output pipe(): $!";
        pipe $err, $ERR or croak "errput pipe(): $!";

        # an extra pipe to communicate exec() failure
        pipe my $stat_r, my $stat_w;

        # create the child process
        $pid = fork;
        croak "Can't fork: $!" if !defined $pid;

        if ($pid) {

            # parent won't use those handles
            close $stat_w;
            close $IN;
            close $OUT;
            close $ERR;

            # failed to fork+exec?
            my $mesg = do { local $/; <$stat_r> };
            die $mesg if $mesg;
        }
        else {    # kid

            # use $stat_r to communicate errors back to the parent
            eval {

                # child won't use those handles
                close $stat_r;
                close $in;
                close $out;
                close $err;

                # setup process group if possible
                setpgrp 0, 0 if $Config{d_setpgrp};

                # close $stat_w on exec
                my $flags = fcntl( $stat_w, F_GETFD, 0 )
                    or croak "fcntl GETFD failed: $!";
                fcntl( $stat_w, F_SETFD, $flags | FD_CLOEXEC )
                    or croak "fcntl SETFD failed: $!";

                # associate STDIN, STDOUT and STDERR to the pipes
                my ( $fd_IN, $fd_OUT, $fd_ERR )
                    = ( fileno $IN, fileno $OUT, fileno $ERR );
                open \*STDIN, "<&=$fd_IN"
                    or croak "Can't open( \\*STDIN, '<&=$fd_IN' ): $!";
                open \*STDOUT, ">&=$fd_OUT"
                    or croak "Can't open( \\*STDOUT, '<&=$fd_OUT' ): $!";
                open \*STDERR, ">&=$fd_ERR"
                    or croak "Can't open( \\*STDERR, '<&=$fd_ERR' ): $!";

                # and finally, exec into @cmd
                exec( { $cmd[0] } @cmd )
                    or do { croak "Can't exec( @cmd ): $!"; }
            };

            # something went wrong
            print $stat_w $@;
            close $stat_w;

            # DIE DIE DIE
            eval { require POSIX; POSIX::_exit(255); };
            exit 255;
        }
    }

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

    # trace: should collapse into a coderef (or nothing)
    my $logger;
    if ( my $trace = $o->{trace} ) {
        $logger
            = ref $trace eq 'GLOB' ? sub { print {$trace} shift, "\n" }
            : blessed $trace && $trace->can('print')
                                   ? sub { $trace->print( shift() . "\n" ) }
            : ref $trace eq 'CODE' ? $trace
            :                        sub { print STDERR shift, "\n" };
        $logger->( "System::Command: $pid - @cmd" );
        $logger->( "System::Command: $pid - $_ = $o->{$_}" )
            for grep { $_ ne 'env' } sort keys %$o;
        $logger->( "System::Command: $pid - \$ENV{$_} = $o->{env}{$_}" )
            for keys %{$o->{env}};
    }

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
        cmdline  => [@cmd],
        options  => $o,
        pid      => MSWin32 ? $pid->{KIDS}[0]{PID} : $pid,
        stdin    => $in,
        stdout   => $out,
        stderr   => $err,
        trace    => $logger,
      ( _ipc_run => $pid )x!! MSWin32,
    }, $class;

    # create the subprocess reaper and link the handles and command to it
    ${*$in} = ${*$out} = ${*$err} = $self->{reaper}    # typeglobs FTW
        = System::Command::Reaper->new($self);

    return $self;
}

sub spawn {
    my ( $class, @cmd ) = @_;
    return @{ $class->new(@cmd) }{qw( pid stdin stdout stderr )};
}

# delegate those to the reaper
sub is_terminated { $_[0]{reaper}->is_terminated() }
sub close         { $_[0]{reaper}->close() }

1;

__END__

# ABSTRACT: Object for running system commands

=head1 SYNOPSIS

    use System::Command;

    # invoke an external command, and return an object
    $cmd = System::Command->new( @cmd );

    # options can be passed as a hashref
    $cmd = System::Command->new( @cmd, \%option );

    # $cmd is basically a hash, with keys / accessors
    $cmd->stdin();     # filehandle to the process stdin (write)
    $cmd->stdout();    # filehandle to the process stdout (read)
    $cmd->stderr();    # filehandle to the process stdout (read)
    $cmd->pid();       # pid of the child process

    # find out if the child process died
    if ( $cmd->is_terminated() ) {
        # the handles are not closed yet
        # but $cmd->exit() et al. are available if it's dead
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

System::Command is a class that launches external system commands
and return an object representing them, allowing to interact with them
through their C<STDIN>, C<STDOUT> and C<STDERR> handles.

=head1 METHODS

System::Command supports the following methods:

=head2 new

    my $cmd = System::Command->new( @cmd )

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

If several option hashes define the C<env> key, the hashes they point
to will be merged into one (instead of the last one taking precedence).

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

The System::Command object returned by C<new()> has a number of
attributes defined (see below).


=head2 close

    $cmd->close;

Close all pipes to the child process, collects exit status, etc.
and defines a number of attributes (see below).

=head2 is_terminated

    if ( $cmd->is_terminated ) {...}

Returns a true value if the underlying process was terminated.

If the process was indeed terminated, collects exit status, etc.
and defines the same attributes as C<close()>, but does B<not> close
all pipes to the child process.


=head2 spawn

    my ( $pid, $in, $out, $err ) = System::Command->spawn(@cmd);

This shortcut method calls C<new()> (and so accepts options in the same
manner) and directly returns the C<pid>, C<stdin>, C<stdout> and C<stderr>
attributes, in that order.


=head2 Accessors

The attributes of a System::Command object are also accessible
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
while the anonymous System::Command object has been destroyed. Once
C<$fh> is destroyed, the subprocess will be reaped, thus avoiding zombies.
(L<System::Command::Reaper> undertakes this process.)

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

Note that System::Command uses C<waitpid()> to catch the status
information of the child processes it starts. This means that if your
code (or any module you C<use>) does something like the following:

    local $SIG{CHLD} = 'IGNORE';    # reap child processes

System::Command will not be able to capture the C<exit>, C<core>
and C<signal> attributes. It will instead set all of them to the
impossible value C<-1>, and display the warning
C<Child process already reaped, check for a SIGCHLD handler>.

To silence this warning (and accept the impossible status information),
load System::Command with:

    use System::Command -quiet;

It is also possible to more finely control the warning by setting
the C<$System::Command::QUIET> variable (the warning is not emitted
if the variable is set to a true value).

If the subprocess started by System::Command has a short life
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

Thanks to Alexis Sukrieh (SUKRIA) who, when he saw the description of
L<Git::Repository::Command> during my talk at OSDC.fr 2010, asked
why it was not an independent module. This module was started by
taking out of L<Git::Repository::Command> 1.08 the parts that
weren't related to Git.

Thanks to Christian Walde (MITHALDU) for his help in making this
module work better under Win32.

The L<System::Command::Reaper> class was added after the addition
of Git::Repository::Command::Reaper in L<Git::Repository::Command> 1.11.
It was later removed from L<System::Command> version 1.03, and brought
back from the dead to deal with the zombie apocalypse in version 1.106.

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

Copyright 2010-2013 Philippe Bruhat (BooK).

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

