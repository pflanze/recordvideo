#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Recordvideo::Processes

=head1 SYNOPSIS

=head1 DESCRIPTION

Extend Processes functionality.

=cut


package Chj::Recordvideo::Processes;
@ISA="Exporter"; require Exporter;
@EXPORT=qw(Stop
	   Stop_then
	   maybe_pop_then
	   push_then);
@EXPORT_OK=qw();
%EXPORT_TAGS=(all=>[@EXPORT,@EXPORT_OK]);

use strict;

sub Stop ($) {
    my ($maybe_process)=@_;
    if ($maybe_process) {
	$maybe_process->terminate;
	undef $_[0]; # hacky?
    }
}

our $uuid2then;
sub push_then ($$) {
    my ($process,$cont)=@_;
    my $uuid= $process->uuid;
    push @{ $$uuid2then{ $uuid } }, $cont;
}
sub maybe_pop_then ($) {
    my ($process)=@_;
    my $uuid= $process->uuid;
    if (my $then= $$uuid2then{ $uuid }) {
	my $cont= pop @$then;
	delete $$uuid2then{ $uuid } unless @$then;
	$cont
    } else {
	()
    }
}
sub then_is_zombie ($$) {
    my ($process,$reapit)=@_;
    my $uuid= $process->uuid;
    if (exists $$uuid2then{ $uuid }) {
	delete $$uuid2then{ $uuid }
	    if $reapit;
	1
    } else {
	0
    }
}

sub Stop_then ($$) {
    my ($maybe_process, $cont)=@_;
    if ($maybe_process) {
	if (then_is_zombie $maybe_process, 1) {
	    @_=(); goto $cont;
	} else {
	    push_then $maybe_process, $cont;
	    # XX also add a timeout event, so as to check with "kill 0"
	    # whether still around?
	    $maybe_process->terminate;
	    undef $_[0]; # hacky?
	}
    } else {
	@_=(); goto $cont
    }
}



1
