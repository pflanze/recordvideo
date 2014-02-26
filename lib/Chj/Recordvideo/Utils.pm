#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Recordvideo::Utils

=head1 SYNOPSIS

=head1 DESCRIPTION


=cut


package Chj::Recordvideo::Utils;
@ISA="Exporter"; require Exporter;
@EXPORT=qw(DBG
	   xmlquote
	   xlogspawn
	   xlogsystem xxINTlogsystem make_maybe_result2error
	 );
@EXPORT_OK=qw(with_setsid_SIGINT); # don't use, delete?
%EXPORT_TAGS=(all=>[@EXPORT,@EXPORT_OK]);

use strict;

use Chj::singlequote 'singlequote_sh';
use Carp;

sub DBG {
    carp "DBG: ", join(" ",map { singlequote_sh $_ } @_);
    @_
}


sub xmlquote ($) {
    my ($str)=@_;
    $str=~ s/&/&amp;/sg;
    $str=~ s/</&lt;/sg;
    $str=~ s/>/&gt;/sg;
    $str
}


use POSIX qw(setsid SIGINT);
sub with_setsid_SIGINT ($) {
    my ($thunk)=@_;
    setsid or die $!;
    local $SIG{INT}= sub {
	kill SIGINT, -$$ # we ourselves are protected since in signal handler

	    # Only issue is, if the program (main sid) is killed
	    # through another signal (HUP?), then it will
	    # not stop here. Thus, need the main program
	    # to catch SIGHUP etc. and proxy it to
	    # killall (which is SIGINT)! --- XXX ehr, no,
	    # kill each pid separately, since this is no
	    # in the group anymore *!* well still Stop
	    # actions?  OR, change xlogsystem so that it
	    # proxies the signal to the child; messy
	    # though? well, correct flags, perhaps
	    # work. signal handler needed,too. hell,
	    # posix. non localetc, good for vm creations
	    # b nth els?  Perl me ? l ?
    };
    &$thunk;
    # bad, race condition. This is a hack.
}

use Chj::xpipe;
use Chj::xperlfunc;

sub xlogspawn {
    my ($logfh,@cmd)=@_;
    $logfh->xprint("xlogspawn: ", (join " ",map{singlequote_sh $_} @cmd),"\n");
    my ($r,$self)=xpipe;
    bless $self, "Chj::IO::Command";
    $self->xlaunch3(undef,$logfh,$logfh,@cmd);
    my $pid= $self->pid;
    $self->finish_nowait; # stop destructor from calling wait
    $pid
};

sub xlogsystem {
    my ($logfh,@cmd)=@_;
    if (my $pid= xfork) {
	xwaitpid $pid, 0;
	$?
    } else {
	# assume Chj::IO::File object
	$logfh->xdup2(1);
	$logfh->xdup2(2);
	xexec (@cmd);
	exit 127; # shouldn't normally get here
    }
}

{
    package Chj::xxINTlogsystem::Exception;
    use Chj::Struct ["message","logpath","interrupted"];
    _END_
}

# variant that proxies SIGINT to the child, and throws exception

# whether to unlink the logfile on success:
# 0= never
# 1= if process does exit(0)
# 2= also unlink if SIGINT was sent to process
our $xxINTlogsystem_unlink= 2;

# $logfh: must support xdup2 and path methods
# $capture_stdout: boolean
# $cmd: array passed to exec
sub xxINTlogsystem ($$$) {
    my ($logfh, $capture_stdout, $cmd)=@_;
    my $interrupted= 0;
    my $proxied= 0;
    my $pid;
    local $SIG{INT}= sub {
	$interrupted=1;
	$proxied= kill SIGINT, $pid
	    if defined $pid;
    };
    if ($pid= xfork) {
	if ($interrupted) {
	    kill SIGINT, $pid
		unless $proxied;
	}
	xwaitpid $pid;
	if ($? == 0) {
	    unlink $logfh->path
		if $xxINTlogsystem_unlink;
	} else {
	    unlink $logfh->path
		if ($xxINTlogsystem_unlink == 2 and $interrupted);
	    die Chj::xxINTlogsystem::Exception->new
		("Subprocess $$cmd[0] exited with status $?",
		 $logfh->path,
		 $interrupted);
	}
    } else {
	$SIG{INT}= undef;
	if ($interrupted) {
	    #warn "interrupted";#
	    #exit 127;
	    #or
	    kill SIGINT, $$
	}
	$logfh->xdup2(2);
	$logfh->xdup2(1)
	    if $capture_stdout;
	xexec (@$cmd);
	exit 127; # shouldn't normally get here
    }
}
# That should be safe, isn't it?
# Is there a POSIX proof tool/library?

use Data::Dumper;

use Chj::xopen 'xopen_read';

sub make_maybe_result2error ($) {
    my ($error)= @_;
    sub ($) {
	my ($maybe_result)= @_;
	if (defined $maybe_result) {
	    my $result= $maybe_result;
	    if (UNIVERSAL::isa($result, 'Chj::ProcessResult::Exception')) {
		my $msg= $result->value;
		if (UNIVERSAL::isa($msg, 'Chj::xxINTlogsystem::Exception')) {
		    if ($msg->interrupted) {
			# Always OK?
			warn "exception due to interrupt signal"
			    if $main::verbose;
		    } else {
			my $logstr= xopen_read($msg->logpath)->xcontent;
			# XXX and what about exceptions thrown from here?
			&$error( $msg->message, $logstr);
		    }
		} else {
		    &$error( "Got error from subprocess:", Dumper($maybe_result));
		}
	    } elsif (UNIVERSAL::isa($result, 'Chj::ProcessResult::Value')) {
		warn "# end value, ignore"
		    if $main::verbose;
	    } elsif (UNIVERSAL::isa($result, 'Chj::ProcessResult::Signal')
		     and $result->value eq "INT") {
		warn "# killed in Perl code (not xxINTlogsystem), ignore"
		    if $main::verbose;
	    } else {
		&$error( "Got unexpected message from subprocess:", Dumper($maybe_result));
	    }
	}
    }
}


1
