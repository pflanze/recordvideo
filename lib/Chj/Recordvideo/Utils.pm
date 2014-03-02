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
           Subcmd pipeline_Process_with_prethunk
           logfh
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


# ------------------------------------------------------------------

use Chj::xtmpfile;

sub logbase () {
    # config ("basedir")."/." -- not good, if not mounted! Also, autocleaning.
    "/tmp/"
}

sub logfh ($) {
    my ($basename)=@_;
    my $fh= xtmpfile (logbase.$basename.".log-");
    $fh->autoclean(0);
    $fh
}


use Chj::xpipe;
use POSIX 'SIGINT';

{package PFLANZE::Subcmd;
 use Chj::Struct ["logname", "cmd", "maybe_prethunk"];
 _END_}
sub Subcmd ($$;$) {
    PFLANZE::Subcmd->new(@_)
}

# a for loop that signals whether it's the last item
sub forlast ($$) {
    my ($ary,$proc)=@_;
    my $len= @$ary;
    for my $i (0..$len-2) {
	&$proc ($$ary[$i],0)
    }
    &$proc ($$ary[$len-1],1)
}

#sub boundary_array_fold_right ($$) {

sub array_fold_withterminal ($$$) {
    # passes additional flag to fn whether it is the last item
    my ($fn, $val, $ary)=@_;
    my $last_i = $#$ary;
    for my $i (0..$last_i) {
	$val= &$fn ($$ary[$i],$val,$i==$last_i);
    }
    $val
}

use Chj::TEST;

TEST { array_fold_withterminal
	   sub{ my ($v,$res,$is_last)=@_; [$v,$is_last,$res]},
	   "START",
	   [10,20,30] }
  [ 30, 1,
    [ 20, '',
      [ 10, '',
	'START']]];

use Chj::Processes;

sub pipeline_Process_with_prethunk ($$;$) {
    my ($prethunk, $subcmds, $maybe_collector) = @_;
    Process {
	#my $processname= "pipeline_Process-".join("-",map { $_->cmd->[0] } @$subcmds);
	#psname $processname;
	&$prethunk;
	my %pids; # pid => killed?
	my $interrupted=0;
	#local
	$SIG{INT}= sub {
	    $interrupted=1;
	    for (sort keys %pids) {
		kill SIGINT, $_;
		$pids{$_}=1;
	    }
	};

	array_fold_withterminal
	    (sub {
		my ($subcmd,$maybe_frompipe,$is_last)=@_;
		if ($interrupted) {
		    if ($maybe_frompipe) {
			my ($r,$w)= @$maybe_frompipe;
			$r->xclose;
		    }
		    undef
		} else {
		    my $maybe_topipe= $is_last ? undef : [xpipe];
		    if (my $pid= xfork) {
			$pids{$pid}=0;
			# (there's still a race between creating the
			# hash key and setting it to 0, right? then
			# that process will be killed twice)
			if ($maybe_frompipe) {
			    my ($r,$w)= @$maybe_frompipe;
			    $r->xclose;
			}
			if ($maybe_topipe) {
			    my ($r,$w)= @$maybe_topipe;
			    $w->xclose;
			}
			$maybe_topipe
		    } else {
			if ($maybe_frompipe) {
			    my ($r,$w)= @$maybe_frompipe;
			    $r->xdup2 (0);
			}
			if ($maybe_topipe) {
			    my ($r,$w)= @$maybe_topipe;
			    $r->xclose;
			    $w->xdup2 (1);
			}
			if (my $prethunk= $subcmd->maybe_prethunk) {
			    &$prethunk;
			}
			xxINTlogsystem (logfh ($subcmd->logname),
					0, # !
					$subcmd->cmd);
			exit 0;
		    }
		}
	     },
	     undef,
	     $subcmds);
	if ($interrupted) {
	    for (sort keys %pids) {
		kill SIGINT, $_
		    unless $pids{$_}
	    }
	}
	# no need for xxwaitpid as the subprocesses are
	# sending their errors directly
	xwaitpid $_ for sort keys %pids;
    } $maybe_collector;
}

# ------------------------------------------------------------------

1
