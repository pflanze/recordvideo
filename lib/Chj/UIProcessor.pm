#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::UIProcessor

=head1 SYNOPSIS

 use Chj::UIProcessor;

 our $dosomething= UIProcessor {
     my (@args)=@_;
     ..
 };
 ..
  Process { # or fork or whatever
     ...
     &$dosomething(@args);
  }

 # ---or---

 use Chj::UIProcessor;

 our $dosomething= UIProcess {
     my (@args)=@_;
     ..
 };
 ..
  Process { # or fork or whatever
     ...
     $dosomething->send(@args);
  }


=head1 DESCRIPTION

Registers a LocalProcess_handler with Gtk (using PFLANZE::Watcher),
returns a procedure that sends to this handler.

Also sets $SIG{PIPE} to "IGNORE" and creates a new session using
setsid, and provides killall. [hacky, move to somewhere else?]

=cut


package Chj::UIProcessor;
@ISA="Exporter"; require Exporter;
@EXPORT=qw(UIProcessor UIProcess killall);
@EXPORT_OK=qw();
%EXPORT_TAGS=(all=>[@EXPORT,@EXPORT_OK]);

use strict;

use Chj::Processes;
use Chj::Glib::Watcher;

use POSIX qw(setsid SIGTERM);
our $sessid= setsid; $sessid < 0 and $sessid= $$;
sub killall {
    local $SIG{TERM}= "IGNORE"; kill SIGTERM, -$sessid;
}
$SIG{PIPE}= "IGNORE";
##x

our $UIProcess_id=0;
our $UIProcess_table={};

our $UIProcess_handler= LocalProcess_handler {
    my ($id, @args)= @_;
    $$UIProcess_table{$id}->(@args);
    ## eval?
};

# register it:
our $UIProcess_watcher= Chj::Glib::Watcher->new
    (fd=> $UIProcess_handler->socket->fileno,
     thunk=> $UIProcess_handler->iohandler);

{
    package Chj::UIProcess;
    use Chj::Struct ["id","process"];
    sub send {
	my $s=shift;
    	$$s{process}->send($$s{id}, @_)
    }
    _END_
}

sub _UIProcess {
    my ($proc)=@_;
    # send a closure 'over the channel'? no, send it an ID that maps
    # to $proc
    my $id= $UIProcess_id++;
    $$UIProcess_table{$id}= sub {
	my (@args)=@_;
	$UIProcess_watcher->end; # necessary? perhaps to avoid leaking?
	$UIProcess_watcher= Chj::Glib::Watcher->new
	    (fd=> $UIProcess_handler->socket->fileno,
	     thunk=> $UIProcess_handler->iohandler);
	&$proc(@args);
    };
    my $process= $UIProcess_handler->process;
    Chj::UIProcess->new($id,$process)
}

sub UIProcessor (&) {
    my ($proc)=@_;
    my $uiprocess= _UIProcess($proc);
    sub {
	$uiprocess->send(@_)
    }
}

sub UIProcess (&) {
    my ($proc)=@_;
    _UIProcess($proc)
}


1
