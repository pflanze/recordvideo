#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::IO::Socket::UNIX

=head1 SYNOPSIS

=head1 DESCRIPTION


=cut


package Chj::IO::Socket::UNIX;

use strict;

use Chj::IO::File;
use IO::Socket::UNIX;

our @ISA=qw(IO::Socket::UNIX Chj::IO::File);

sub new_xconnect_peer {
    my $class=shift;
    @_==1 or die;
    my ($path)=@_;
    if (my $s= IO::Socket::UNIX->new(Peer=> $path)) {
	bless $s, $class
    } else {
	die "'$path': $!"
    }
}

sub new_xlisten {
    my $class=shift;
    @_==1 or die;
    my ($path)=@_;
    if (my $s= IO::Socket::UNIX->new
	(Local=> $path,
	 Type=> SOCK_STREAM,
	 Listen=> 10, # not a boolean, but a queue length right?
	 #ReuseAddr=> 1, doesn't help. thus unlink
	)) {
	bless $s, $class
    } else {
	die "'$path': $!"
    }
}

sub quotedname {
    my $s=shift;
    "unix domain socket ".Chj::IO::File::_quote(scalar $s->name)
}

1
