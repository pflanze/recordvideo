#
# Copyright 2014 by Christian Jaeger, ch at christianjaeger ch
# Published under the same terms as perl itself
#
# $Id$

=head1 NAME

Chj::Config

=head1 SYNOPSIS

=head1 DESCRIPTION

See test cases in Chj/Config.pm

=cut

package Chj::Config::Test;
use strict;

use Chj::TEST;
use Chj::xtmpdir;
use Chj::FP::Hash;
use Chj::singlequote 'singlequote_many';

our $testdir;
our $config;
our $default_config;
our $configpath;

our $quit_exception= bless [], "Chj::Config::Test::QuitException";
our $msgs;
sub note {
    my($msg)=@_;
    push @$msgs, ["NOTE", $msg];
}
sub make_confirm {
    my ($accept)=@_;
    sub {
	my($id,$msg)=@_;
	push @$msgs, ["CONFIRM", $id, $accept];
	if ($accept) {
	    #ok
	} else {
	    die $quit_exception;
	}
    }
}
sub make_ask {
    my ($answer)=@_;
    sub {
	my($id,$msg,$buttons)=@_;
	push @$msgs, ["ASK", $id, $$buttons[$answer]];
	$answer
    }
}
sub error {
    die [@_], "Chj::Config::Test::ErrorException"
}

# Program init
TEST {
    $testdir= xtmpdir;
    $default_config= +{
		       a=> "one",
		       b=> "two",
		       c=> 1,
		      };
    $configpath= "$testdir/conf";
    $config= Chj::Config->new($configpath, $default_config);
    ref $config
}
  "Chj::Config";

# 'Welcome case' (first time program run)
TEST {
    $msgs=[];
    $config= $config->do_load
      (\&note, make_confirm(1), make_ask(0));
    $msgs
} [];

TEST {
    $config= $config->set(a=> "one a")->set(c=> 0);
    $msgs=[];
    $config->do_save (\&error);
    $msgs
} [];

# normal startup case, unchanged defaultsppp
TEST {
    $config= Chj::Config->new($configpath, $default_config)
      ->do_load
	(\&note, make_confirm(1), make_ask(0));
    $msgs
} [];

# changed defaults, user wants to keep his value
TEST {
    $msgs=[];
    $default_config= hash_set(hash_delete ($default_config, "c"), a=> "one aa");
    $config= Chj::Config->new($configpath, $default_config)
      ->do_load
	(\&note, make_confirm(1), make_ask(0));
    $config->do_save (\&error);
    $msgs
}
  [['NOTE', "userchange-dropped"],
   ['ASK', "changed-both", 'keep your value']];

# changing default to the user's value
TEST {
    $msgs=[];
    $default_config= hash_set($default_config, a=> "one a");
    $config= Chj::Config->new($configpath, $default_config)
      ->do_load
	(\&note, make_confirm(1), make_ask(0));
    $config->do_save (\&error);
    $msgs
} [];
# It will silently modify the user's value on the next change of that
# default, though! heh

# changing default, user accepts change; changing another default that
# the user didn't change, accepts it, too.
TEST {
    $msgs=[];
    $config= $config->set(a=> "my a");
    $config->do_save (\&error);

    $default_config= hash_set(hash_set($default_config, a=> "one aa"), b=> "two b");
    $config= Chj::Config->new($configpath, $default_config, 1) # 1 = be verbose!
      ->do_load
	(\&note, make_confirm(1), make_ask(1));
    $msgs
} [['ASK', "changed-both", 'use the new default'],
  ['ASK', "changed-default", 'upgrade to the new value']];

TEST{
    [$config->get("a"), $config->get("b")]
} ["one aa", "two b"];

# same thing, but not verbose:
TEST {
    $msgs=[];
    $config= Chj::Config->new($configpath, $default_config) # not verbose
      ->do_load
	(\&note, make_confirm(1), make_ask(1));
    $msgs
} [['ASK', "changed-both", 'use the new default']];

TEST{
    [$config->get("a"), $config->get("b")]
} ["one aa", "two b"];



{
    package Chj::Config;
    use YAML qw(LoadFile);
    use Chj::FP::Hash;

    use Chj::Struct ["path", "defaults", "be_verbose"];

    sub do_load {
	my $s=shift; @_==3 or die;
	my ($do_notify,$do_confirm,$do_ask)=@_;
	# &$do_notify($id,$msg): should just have an "Ok" button, return please.
	# &$do_confirm($id,$msg): should ask "Quit", "Ok", on Quit, don't return!
	# &$do_ask($id,$msg,$buttons): return with the index of the button pressed.
	# $msg is an array of strings, one per line/paragraph. $id is
	# a static string that identifies the kind of question/message.

	my ($path,$defaults)= ($s->path, $s->defaults);

	my $usedefaults= sub {
	    Chj::Config::Instance->new ($s, $defaults, 1)  # really mark as modified?
	};
	if (-e $path) {
	    if (defined (my $olddefaults_and_values= LoadFile($path))) {
		my ($olddefaults,$oldvalues) = @$olddefaults_and_values{"defaults", "values"};
		if ($olddefaults and $oldvalues) {
		    my $changes_defaults= hash_diff($olddefaults,$defaults);
		    my $changes_user= hash_diff($olddefaults,$oldvalues);

		    my $config= Chj::Config::Instance->new($s, $oldvalues, 0);
		    # ^ no need to mark for saving so far
		    for my $key (hashes_keys $olddefaults, $defaults, $oldvalues) {
			my $defchange= $$changes_defaults{$key};
			my $userchange= $$changes_user{$key};
			if (defined $defchange) {
			    if ($defchange eq 'unchanged') {
				# keep value
			    } elsif ($defchange eq 'changed') {
				my $oldvalue= $$olddefaults{$key};
				my $newvalue= $$defaults{$key};
				my $yourvalue= $$oldvalues{$key};
				if (defined $userchange) {
				    if ($userchange eq 'unchanged') {
					if ($s->be_verbose) {
					    my $answer= &$do_ask
						("changed-default",
						 ["Configuration change",
						  "This application now uses a different default value for '$key'. You did not change this setting from its old default, thus probably you will be fine to use the new value. Note that the old value may not work anymore due to changes in the application.",
						  "You can always change the settings later by visiting the Edit->Preferences menu entry.",
						  "old value: $oldvalue",
						  "new value: $newvalue"
						 ],
						 ["keep the old value",
						  "upgrade to the new value"]);
					    $config= $config->set
						($key,
						 (($answer==0) ? $oldvalue :
						  ($answer==1) ? $newvalue :
						  die "bug"));
					} else {
					    $config= $config->set($key, $newvalue);
					}
				    } elsif ($userchange eq 'changed') {
					if ($yourvalue eq $newvalue) {
					    # default has changed to what the user was using anyway!
					    # No change necessary.
					    # XX: in the case of changed default that
					    # was not touched, the code says "should be ok" though; inconsistent.
					} else {
					    my $answer= &$do_ask
						("changed-both",
						 ["Configuration change",
						  "This application now uses a different default value for '$key'. Also, you did change this setting in the past. Which value should be used?",
						  "You can always change the settings later by visiting the Edit->Preferences menu entry.",
						  "old default: $oldvalue",
						  "your value: $yourvalue",
						  "new default: $newvalue",
						 ],
						 ["keep your value",
						  "use the new default"]);
					    $config= $config->set
						($key,
						 (($answer==0) ? $yourvalue :
						  ($answer==1) ? $newvalue :
						  die "bug"));
					}
				    } elsif ($userchange eq 'added') {
					&$do_notify("odd-manually-added-value",
						    ["Odd, your configuration has a value added for key '$key' but no entry for its default; going to use the new default.",
						     "your value: $yourvalue",
						     "new default: $newvalue",
						    ]);
					$config= $config->set($key, $newvalue);
				    } elsif ($userchange eq 'deleted') {
					&$do_notify("odd-manually-removed-value",
						    ["Odd, your configuration does not have a value for key '$key' although there was an entry for its default; going to use the new default as the value.",
						     "old default: $oldvalue",
						     "new default: $newvalue",
						    ]);
					$config= $config->set($key, $newvalue);
				    } else {
					die "bug";
				    }
				} else {
				    # unknown key in userchange. odd, too. can't be right?
				    warn "bug";
				}
			    } elsif ($defchange eq 'added') {
				# check whether there was a user value even when there was no default?
				# this is getting tiresome, right? just ignore right?
				$config= $config->set($key, $$defaults{$key});
			    } elsif ($defchange eq 'deleted') {
				my $oldvalue= $$olddefaults{$key};
				my $yourvalue= $$oldvalues{$key};
				# give note if user changed the value?
				&$do_notify("userchange-dropped",
					    ["Configuration change",
					     "This application now does not use the configuration for '$key' anymore. You did change this value from its default in the past; this change of yours will be dropped now.",
					     "You can always change the settings later by visiting the Edit->Preferences menu entry.",
					     "old default: $oldvalue",
					     "your value: $yourvalue",
					    ]);
				$config= $config->_delete($key);
			    } else {
				die "bug? for key '$key', defchange '$defchange'";
			    }
			} else {
			    my $oldvalue= $$olddefaults{$key};
			    my $newvalue= $$defaults{$key};
			    #my $yourvalue= $$oldvalues{$key};
			    # warn "I think I'm silently dropping user
			    # config value now, since the default
			    # config neither had this value in the
			    # past nor now: key '$key'";
			    if (defined $$oldvalues{$key}) {
				&$do_notify("odd-manually-deleted",
					    ["Odd, your configuration does have a value for key '$key' although there was an entry for its default; going to use the new default as the value.",
					     "old default: $oldvalue",
					     "new default: $newvalue",
					    ]);
			    } else {
				##warn?
				die "bug? for key '$key', defchange undef";
			    }
			}
		    }
		    $config
		} else {
		    &$do_confirm("config-in-invalid-format",
				 ["Invalid configuration format",
				  "The current configuration does not follow the expected format, "
				  ."going to use the default configuration instead.",
				  "You can always change the settings later by visiting the Edit->Preferences menu entry.",
				  "The configuration file is at: $path"]);
		    &$usedefaults
		}
	    } else {
		&$do_notify ("config-not-readable-yaml",
			     ["Unreadable configuration format",
			      "Can't read configuration from '$path', going to use the defaults.",
			      "You can always change the settings later by visiting the Edit->Preferences menu entry.",
			     ]);
		&$usedefaults
	    }
	} else {
	    # &$do_notify ("welcome", ["Welcome"]);
	    &$usedefaults
	}
    }

    sub set { die "you need to run do_load on this then run this method on the result" }
    *set_values=*set;
    *get=*set;
    *do_save=*set;

    _END_
}

{
    package Chj::Config::Instance;
    use Chj::xsysopen ':all';
    use Chj::xperlfunc ":all";
    use YAML qw(DumpFile);
    use Chj::FP::Hash;

    use Chj::Struct
	["config", # Chj::Config object
	 "values", # hashtable; bad name?
	 "is_modified", # internally maintained, whether it needs saving
	];

    # functional setter
    sub set {
	my $s=shift; @_==2 or die;
	my ($key,$val)=@_;
	exists $s->config->defaults->{$key} or die "unknown config key '$key'";
	ref($s)->new($s->config,
		     hash_set($s->values, $key, $val),
		     1)
    }

    sub set_values {
	my $s=shift; @_==1 or die;
	my ($values)=@_;
	ref($s)->new($s->config, $values, 1)
    }

    sub set_is_modified {
	my $s=shift; @_==1 or die;
	my ($v)=@_;
	ref($s)->new($s->config, $s->values, $v)
    }

    sub get {
	my $s=shift; @_==1 or die;
	my ($key)=@_;
	exists $s->config->defaults->{$key} or die "unknown config key '$key'";
	$s->values->{$key}
    }

    # only used internally
    sub _delete {
	my $s=shift; @_==1 or die;
	my ($key)=@_;
	ref ($s)->new ($s->config,
		       hash_delete ($s->values, $key),
		       1)
    }

    sub do_save {
	my $s=shift;
	@_==1 or die;
	my ($error)=@_;

	if ($s->is_modified) {
	    my $configpath= $s->config->path;
	    my $tmp= $configpath.".tmp";

	    my $err= sub {
		&$error ("Could not save configuration.", "Configuration file: $configpath", @_)
	    };

	    eval {
		# backup old one if there
		my $bck= $configpath.".bck";
		my $bcktmp= $configpath.".bcktmp";
		unlink $bcktmp;
		link $configpath, $bcktmp;

		# make file private:
		xsysopen ($tmp, O_CREAT, 0600);
		# actually write it:
		$!=0; # necessary (for the cases where DumpFile fails for other reasons)?
		if (DumpFile $tmp, +{defaults=> $s->config->defaults,
				     values=> $s->values}) {
		    xrename $tmp, $configpath;
		    rename $bcktmp, $bck;
		} else {
		    &$err ("DumpFile failed.",  "OS error: $!")
		}
		1
	    } || do {
		&$err("Exception: $@");
	    };
	    $s->set_is_modified(0)
	} else {
	    warn "no changes to config to be saved";
	    $s
	}
    }

    _END_
}

