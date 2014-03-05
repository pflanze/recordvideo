
# dialog by way of Gtk3::Dialog
sub dialog ($$$$) {
    @_==4 or die;
    my ($title,$msg_args,$buttons,$other_id)=@_;
    # there's no new_with_buttons somehow, man.
    local our $dlg= Gtk3::Dialog->new;
    $dlg->set_title("$myname $title");
    # $dlg->set_parent  or set_parent_window? undef
    $dlg->set_modal(1);
    my $i=10;
    for (@$buttons) {
	$dlg->add_button($_, $i++);
    }
    {
	my $box= Gtk3::HBox->new;
	{
	    my $icon= Gtk3::Image->new_from_icon_name
		("dialog-information",
		 6 # GTK_ICON_SIZE_DIALOG
		);
	    $box->add($icon);
	}
	{
	    my $label= Gtk3::Label->new("");
	    $label->set_line_wrap(1);
	    # ^ 'sigh', isn't label being misused anyway?
	    $label->set_markup(dialog_markup flatten $msg_args);
	    $box->add($label);
	}
	$box->set_homogeneous (0);
	$dlg->get_content_area->add($box);
    }
    
    $dlg->set_resizable(1);
    $dlg->show_all; # huh necessary otherwise the content_area does not show?
    my $answer= $dlg->run;
    $dlg->destroy;
    $answer >= 10 ? $answer-10 : $other_id
}

