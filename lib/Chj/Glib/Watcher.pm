#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Glib::Watcher

=head1 SYNOPSIS

 use Chj::Glib::Watcher;
 use Chj::xpipe;
 my ($r,$w)= xpipe;
 our $watcher= Chj::Glib::Watcher->new
	  (fd=> $r->fileno,
	   thunk=> sub {
	       my $buf;
	       $r->xsysread($buf,1) == 1
		 or die "bug?: eof";
	       my $msg= pop @queue;
	       &$proc(@{thaw $msg});
	   });

 $watcher->remove; # or ->end
  # removes it from Glib
 # (There is no DESTROY method.)

=head1 DESCRIPTION


=cut


package Chj::Glib::Watcher;

use strict;

# inspired by
# http://cpansearch.perl.org/src/TVIGNAUD/Gtk3-Helper-0.02/lib/Gtk3/Helper.pm

use Glib;

sub new { # fd=> integer, thunk=>
    my $cl=shift;
    my $s= bless +{@_}, $cl;
    $$s{io_id}= Glib::IO->add_watch
      ($$s{fd},
       'G_IO_IN',
       $$s{thunk},
       undef);
    $$s{hup_id}= Glib::IO->add_watch
      ($$s{fd},
       'G_IO_HUP',
       sub {
	   $s->remove
       },
       undef);
    $s
}

sub remove {
    my $s=shift;
    Glib::Source->remove ($$s{io_id});
    Glib::Source->remove ($$s{hup_id});
    ()
}

sub end;
*end=*remove;

1
