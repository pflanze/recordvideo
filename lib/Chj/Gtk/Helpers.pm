#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Gtk::Helpers

=head1 SYNOPSIS

 use Chj::Gtk::Helpers;

 signal_set($obj, clicked=> $proc1);
 signal_set($obj, clicked=> $proc2); # replaces proc1 with proc2,
   # unlike $obj->signal_connect(clicked=> $proc2) which adds it

=head1 DESCRIPTION


=cut


package Chj::Gtk::Helpers;
@ISA="Exporter"; require Exporter;
@EXPORT=qw(signal_set);
@EXPORT_OK=qw();
%EXPORT_TAGS=(all=>[@EXPORT,@EXPORT_OK]);

use strict;


our $signals_connected= {}; # "$obj" => what => [id, proc]
our $known_signal_what=
    +{
	clicked=> 1,
	activate=> 1,
	"delete-event"=> 1,
	# well there are *tons* of signals, every widget can have their own it seems!
	# and oh WELL I'd love an on_change, but, multiple right?:
	"backspace"=> 1,
	"cut-clipboard"=> 1,
	"delete-from-cursor"=> 1,
	"insert-at-cursor"=> 1,
	"paste-clipboard"=> 1,
	# jez.
	# custom signal!:
	on_change=> [
	    "backspace",
	    "cut-clipboard",
	    "delete-from-cursor",
	    "insert-at-cursor",
	    "paste-clipboard",
	    #"icon-press", nope
	    # from parent class: GtkWidget
	    "key-press-event",
	    "key-release-event",
	    # sigh really. huh. but those made it work.
	    ],
    };

# connect a single signal handler, replacing previously connected ones.
sub signal_set ($$$) {
    my ($obj,$what,$proc)=@_;
    die "1st argument must be an object"
	unless ref $obj;
    my $known= $$known_signal_what{$what};
    die "2nd argument is unknown"
	unless $known;
    die "3rd argument must be a code ref"
	unless ref ($proc) eq "CODE";

    my $connect= sub {
	my ($what)=@_;
	warn "setting $obj '$what'";
	if (my $id_proc= $$signals_connected{"$obj"}{$what}) {
	    $$id_proc[1]= $proc;
	} else {
	    my $id_proc= [undef, $proc];
	    my $id= $obj->signal_connect($what, sub { goto ($$id_proc[1]) });
	    $$id_proc[0]= $id;
	    $$signals_connected{"$obj"}{$what}= $id_proc;
	}
    };

    if (ref ($known) eq "ARRAY") {
	&$connect($_) for (@$known);
    } else {
	&$connect($what);
    }
}

1
