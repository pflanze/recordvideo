#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Process

=head1 SYNOPSIS

=head1 DESCRIPTION

This is the class representing processes. For the Process constructor
see L<Chj::Processes>.

=cut


package Chj::Process;

use strict;

use POSIX 'SIGINT';
# XX should probably use SIGTERM instead!

use Chj::Transmittable;
use Chj::IO::Socket::UNIX;


use Chj::Struct ["pid", "socketpath"];

sub send {
    my $s=shift;
    @_>=1 or die "need at least 1 argument";
    my $sock= Chj::IO::Socket::UNIX->new_xconnect_peer($s->socketpath);
    xtransmit \@_, $sock;
}

sub kill {
    my $s=shift;
    my ($maybe_signal)=@_;
    my $signal = $maybe_signal // SIGINT;
    return CORE::kill $signal, $s->pid;
}

sub terminate {
    my $s=shift;
    $s->kill(SIGINT);
}

sub kill_the_host {
    my $s=shift;
    $s->kill(@_)
}

_END_;

sub uuid;
*uuid= *socketpath;

{
    package Chj::LocalProcess;

    use Chj::Struct []=> "Chj::Process";

    sub kill {
	my $s=shift;
	die "local processes can't be killed normally";
	# since there's no 1:1 mapping from local processes to host
	# processes
    }

    sub kill_the_host {
	my $s=shift;
	$s->SUPER::kill(@_);
    }

    _END_
}

{
    package Chj::LocalProcess::Handler;

    use Chj::Struct ["socket", "process", "handler", "maybe_carer",
		     # need to store copies of relevant fields
		     # separately since the process field is undef
		     # during global destruction. sigh.
		     "pid", # for safe cleanup
		     "socketpath"];

    sub iohandler {
	my $s=shift;
	sub {
	    # called when there is a message to read from the socket
	    #my $res;
	    # but what would $res be good for ? send where? nowhere.
	    if (eval {
		$$s{handler}->($$s{socket}->receive);
		1
	    }) {
		# done
	    } else {
		my $e= $@;
		my $exitmsg= Chj::ProcessResult::Exception->new($e);
		# well. could, of course, still go on? This is not dying! Hmmmm.
		# But still, report errors somewhere?
		my $maybe_carer= $$s{maybe_carer};
		#COPY from Processes.pm except for fully qualifying
		#$Chj::Processes::verbose and moving other copy inside
		if (my $carer= $maybe_carer) {
		    eval {
			$carer->send($exitmsg);
			1
		    } || do {
			#COPY
			my $e= $@;
			if ($e=~ /^.*Broken pipe/m) {
			    warn "note: carer gone away (broken pipe)"
			      if $Chj::Processes::verbose;
			} else {
			    warn "note: exception trying to transmit to carer: $@";
			}
			#/COPY
		    };
		} else {
		    use Data::Dumper;
		    warn "don't have carer, exitmsg: ".Dumper($exitmsg)
		      if $Chj::Processes::verbose;
		}
		#/COPY
	    }
	}
    }

    sub DESTROY {
	my $s=shift;
	unlink $$s{socketpath} if $$ == $$s{pid};
    }

    _END_
}
