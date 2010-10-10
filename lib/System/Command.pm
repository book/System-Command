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
for my $attr (qw( pid stdin stdout stderr exit signal core options )) {
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
        options => $o,
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

    # done!
    $cmd->close();

    # exit information
    $cmd->exit();      # exit status
    $cmd->signal();    # signal
    $cmd->core();      # core dumped? (boolean)

=head1 DESCRIPTION

C<System::Command> is a class that actually launches an external system
commands, allowing to interact with it through its C<STDIN>, C<STDOUT>
and C<STDERR>.

=head1 METHODS

C<System::Command> supports the following methods:

=head2 new( @cmd )

Runs an external command using the list in C<@cmd>.

If C<@cmd> contains a hash reference, it is taken as an I<option> hash.

The recognized keys are:

=over 4

=item C<cwd>

The I<current working directory> in which the command will be run.

=item C<env>

A hashref containing key / values to add to the command environment.

=item C<input>

A string that is send to the command's standard input, which is then closed.

Using the empty string as C<input> will close the command's standard input
without writing to it.

Using C<undef> as C<input> will not do anything. This behaviour provides
a way to modify previous options populated by some other part of the program.

On some systems, some git commands may close standard input on startup,
which will cause a SIGPIPE when trying to write to it. This will raise
an exception.

=back

If the C<Git::Repository> object has its own option hash, it will be used
to provide default values that can be overriden by the actual option hash
passed to C<new()>.

If several option hashes are passed to C<new()>, they will be merged
together with values being overriden by hashes that appear later in the list.

The C<System::Command> object returned by C<new()> has a number of
attributes defined (see below).


=head2 close()

Close all pipes to the child process, and collects exit status, etc.
and defines a number of attributes (see below).

Note that C<close()> is automatically called when the
C<System::Command> object is destroyed.
Annoyingly, this means that in the following example C<$fh> will be
closed when you tried to use it:

    my $fh = System::Command->new( @cmd )->stdout;

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

The PID of the underlying B<git> command.

=item stdin()

A filehandle opened in write mode to the child process' standard input.

=item stdout()

A filehandle opened in read mode to the child process' standard output.

=item stderr()

A filehandle opened in read mode to the child process' standard error output.

=back

After the call to C<close()>, the following attributes will be defined:

=over 4

=item exit()

The exit status of the underlying B<git> command.

=item core()

A boolean value indicating if the command dumped core.

=item signal()

The signal, if any, that killed the command.

=back

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

Copyright 2010 Philippe Bruhat (BooK).

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

