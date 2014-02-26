#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Recordvideo::Devices

=head1 SYNOPSIS

=head1 DESCRIPTION


=cut


package Chj::Recordvideo::Devices;
@ISA="Exporter"; require Exporter;
@EXPORT=qw(get_v4ldevices get_audio_devices);
@EXPORT_OK=qw();
%EXPORT_TAGS=(all=>[@EXPORT,@EXPORT_OK]);

use strict;

use Chj::xopen 'xopen_read';
use Chj::IO::Command;

sub get_v4ldevices {
    my $usb_vendorproduct2text=
      +{
	map {
	    chomp;
	    if (my ($vendor,$product,$text)= /ID ([0-9a-f]{4}):([0-9a-f]{4}) (.*)/) {
		("$vendor:$product"=> $text)
	    } else {
		()
	    }
	} Chj::IO::Command->new_sender("lsusb")->xreadline
	## ^ error checking at end?
       };
    my @p= glob "/sys/class/video4linux/*/name";
    +{
      map {
	  my $path= $_;
	  my ($dev)= $path=~ m|/([^/]+)/name$| or die;
	  my $name= xopen_read ($path)->xcontent;
	  chomp $name;
	  if (my ($vendor,$product)=
	      $name=~ /UVC Camera.*\b([0-9a-f]{4}):([0-9a-f]{4})\b/) {
	      my $text= $$usb_vendorproduct2text{"$vendor:$product"}
		or warn "can't retrieve usb text for $vendor:$product";
	      $text ||= "(could not retrieve desc from lsusb) $name";
	      ("/dev/$dev" => $text)
	  } else {
	      warn "ignoring non-UVC (usb) device: '$dev', name='$name'";
	      ()
	  }
      } @p
     }
}

sub get_audio_devices {
    @_==1 or die;
    my ($for_record)=@_;
    my $cmd= $for_record ? ["arecord","-L" ] : ["aplay", "-L"];
    my $in= Chj::IO::Command->new_sender(@$cmd);
    my %dev;
    my $dev;
    my @nam;
    my $fin1= sub {
	if (defined $dev) {
	    warn "BUG? again seeing '$dev'" if exists $dev{$dev};
	    $dev{$dev}= join(" -- ", map{(/^\s*(.*?)\s*\z/s)[0]} @nam);
	    @nam=();
	}
    };
    while (<$in>) {
	chomp;
	if (/^\s/) {
	    push @nam,$_;
	} else {
	    &$fin1;
	    $dev= $_;
	}
    }
    &$fin1;
    \%dev
}

1
