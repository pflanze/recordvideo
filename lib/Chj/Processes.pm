#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Processes

=head1 SYNOPSIS

 use Chj::Processes;
 use POSIX qw(setsid SIGTERM);
 our $sessid= setsid; $sessid < 0 and $sessid= $$;
 sub killall {
     local $SIG{TERM}= "IGNORE"; kill SIGTERM, -$sessid;
 }
 $SIG{PIPE}= "IGNORE";

 # optional:
 $Chj::Processes::verbose = 1; # default: off
 $Chj::Processes::socketdir = "/foo/bar"; # default: xtmpdir

 my $p= Process {
          my ($q,$current_process)=@_;
          while (my (@msg)= $q->receive) {
              print @msg, "\n"
          }
        } $carer;
        # Process takes an optional second argument, a process
        # that will receive the result of this process's ending, a
        # Chj::ProcessResult::* object.
 $p->send("Hello World");  # dies on some errors
 # other process prints: Hello World
 $p->kill; # sends SIGINT by default

 # to kill everything:
 killall;

 # ------------
 # A variant of a process of which several can exist in the same host
 # process (without using threads), by using an event based approach.

 # 'handler' is a proc that receives a message to handle; it should
 # return quickly afterwards.

 # This returns a Chj::LocalProcess::Handler; use something like:
 #
 my $lphandler= LocalProcess_handler {
    my (@msg)= @_;
    print "local handler: ", @msg, "\n";
 }; # $carer;

 # SOMEIOREGISTER($lphandler->socket, $lphandler->iohandler);
 #
 # iohandler will ignore arguments, read from socket, and call
 # the handler thunk
 my $lp= $lphandler->process;
 $lp->send("Hello World", " and you");
 $lphandler->iohandler->();
 # prints 'local process: Hello World and you'

=head1 DESCRIPTION

Message-passing ('Erlang-like') multiprocessing infrastructure, using
fork, and unix domain sockets. Plus a second 'backend' that does event
based message handling.

Process handles can be sent to other processes like normal messages.

Child processes set up SIGINT and SIGTERM handlers that turn the
signals into exceptions.

=head1 NOTES

Process identifiers can't be used for security like in Erlang (this
module does not even attempt to hide other process identifiers from
listing; problem is, the OS probably wouldn't be secure against
attempts to find the socket paths anyway)

=head1 SEE ALSO

L<Chj::Process>, L<Chj::PClosure>

=cut


package Chj::Processes;
@ISA="Exporter"; require Exporter;
@EXPORT=qw(Process LocalProcess_handler);
@EXPORT_OK=qw();
%EXPORT_TAGS=(all=>[@EXPORT,@EXPORT_OK]);

use strict;

{
    package Chj::ProcessResult;
    use Chj::Struct ["value","sender"];
    _END_;
}

{
    package Chj::ProcessResult::Value;
    use Chj::Struct []=> "Chj::ProcessResult";
    sub give {
	my $s=shift;
	$s->value  # always scalar context?
    }
    _END_;
}

{
    package Chj::ProcessResult::Exception;
    use Chj::Struct []=> "Chj::ProcessResult";
    sub give {
	my $s=shift;
	die($s->value)
    }
    _END_;
}

{
    package Chj::ProcessResult::Signal;
    use Chj::Struct []=> "Chj::ProcessResult";
    sub give {
	my $s=shift;
	die $s
    }
    _END_;
}

{
    package Chj::Process::Queue;
    our @ISA= qw(Chj::IO::Socket::UNIX);
    use Chj::Transmittable ();
    sub receive {
	my $s=shift;
	if (my $fh= $s->accept) {
	    my $msg= Chj::Transmittable::xreceive($fh);
	    close $fh or die "close: $!";
	    @$msg
	} else {
	    die "accept: $!";
	}
    }
}


use Chj::Process;
use Chj::xperlfunc; # ":all";
use Chj::IO::Socket::UNIX;
use Chj::Transmittable;
use Chj::xtmpdir;
use Chj::Random::Formatted 'random_passwd_string';
use Chj::xpipe;

our $socketdir= xtmpdir;
$socketdir->autoclean(0);# XX 2 can't work. hm.


our $verbose= 0;

sub new_Process_socket () {
    my $uuid= random_passwd_string(24);
    my $socketpath= $socketdir."/".$uuid;

    my $sock= Chj::IO::Socket::UNIX->new_xlisten($socketpath);
    # (should it retry on clashes? But then that 'should' "never" happen.)
    bless $sock, "Chj::Process::Queue";

    ($socketpath,$sock)
}

sub Process (&;$) {
    my ($proc, $maybe_carer)=@_;

    # open socket before forking so that there is a guaranteed
    # listener, so that send calls won't fail if they happen before
    # the child is ready.
    my ($socketpath,$sock)= new_Process_socket;

    my ($r,$w)= xpipe; # to transmit the pid
    if (my $pid= xfork) {
	close $sock or warn "?? could not close socket: $!";
	xxwaitpid $pid, 0;
	$w->xclose;
	my $realpid= $r->xcontent;
	new Chj::Process ($realpid, $socketpath)
    } else {
	# heh can also have a process here:
	my $sender= new Chj::Process ($$, $socketpath);
	eval {
	    $r->xclose;
	    # double fork
	    if (my $pid= xfork) {
		$w->xprint($pid);
		$w->xclose;
		# return
	    } else {
		$w->xclose;
		$SIG{INT}= sub {
		    die "SIGINT\n";
		};
		$SIG{TERM}= sub {
		    die "SIGTERM\n";
		};
		eval {
		    my $exitmsg= do {
			my $res;
			if (eval {
			    $res= &$proc($sock, $sender);
			    1
			}) {
			    Chj::ProcessResult::Value->new($res,$sender)
			} else {
			    my $e= $@;
			    if ($e=~ /^SIG([A-Z0-9]+)\n/) {
				Chj::ProcessResult::Signal->new($1,$sender)
			    } else {
				Chj::ProcessResult::Exception->new($e,$sender)
			    }
			};
		    };
		    if (my $carer= $maybe_carer) {
			$carer->send($exitmsg);
		    } else {
			use Data::Dumper;
			warn "don't have carer, exitmsg: ".Dumper($exitmsg)
			  if $verbose;
		    }
		    1
		} || do {
		    my $e= $@;
		    if ($e=~ /^.*Broken pipe/m) {
			warn "note: carer gone away (broken pipe)"
			  if $verbose;
		    } else {
			# can also happen if carer has gone away:
			# No such file or directory at lib/Chj/IO/Socket/UNIX.pm line 35.
			warn "note: exception trying to transmit to carer: $@"
			  if $verbose;
		    }
		};
		unlink $socketpath; # XX necessary, right?
		exit(0);
	    }
	    1
	} || do {
	    exit (1)
	};
	exit(0);
    }
}

{
    package Chj::Processes::Within_pid;
    use Chj::Struct ["pid"];
    _END_
}

sub LocalProcess_handler (&;$) {
    my ($handler, $maybe_carer)=@_;
    my ($socketpath,$sock)= new_Process_socket;
    my $pid= $$;
    my $process= new Chj::LocalProcess ($pid, $socketpath);
    Chj::LocalProcess::Handler->new
	($sock, $process, $handler, $maybe_carer,
	 # due to the way Perl's global destruction mechanism 'works',
	 # $process will be deallocated before the handler, thus can't
	 # be accessed, thus have to store copies here:
	 $pid, $socketpath)
}


1
