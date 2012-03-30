use strict;

my $version = "0.1";
my $script_name = "chatters";

weechat::register($script_name, "Arvydas Sidorenko <asido4\@gmail.com>", $version, "GPL2", "Groups people into chatters and idlers", "", "");
weechat::hook_signal("irc_channel_opened", "channel_joined_cb", "ff");
	  
	  
sub channel_joined_cb
{
	my ($signal, $callback, $callback_data) = @_;
	
	# Bug or not, but the nicks are not yet 'there' if we try to retrieve
	# them on the event. 1ms timer hook seems is enough.
	weechat::hook_timer(1, 0, 1, "print_channel_nicks", $callback_data);
	
	return weechat::WEECHAT_RC_OK;
}

sub print_channel_nicks
{
	my ($callback_data) = @_;
	weechat::print("", "loading nicks...");
	
	if (!defined($callback_data))
	{
			weechat::print("", "no callback data");
	}

	my $server = weechat::buffer_get_string($callback_data, "localvar_server");
	my $channel = weechat::buffer_get_string($callback_data, "short_name");
	weechat::print("", $server);
	weechat::print("", $channel);
	my $nicks = weechat::infolist_get("irc_nick", "", $server.",".$channel);
	die "..." unless defined($nicks);
	if ($nicks eq "")
	{
			weechat::print("", "no nicks to list");
	}
	else
	{
		my $str = "";
		my $cnt = 0;
		while (weechat::infolist_next($nicks))
		{
			$str .= weechat::infolist_string($nicks, "name") . " ";
			$cnt++;
			#weechat::print("", );
		}
		weechat::print("", $cnt."".$str);
	}
	
	my $group = weechat::nicklist_add_group($callback_data, "", "qwerty", "red", "1");
	weechat::nicklist_add_nick($callback_data, $group, "woot", "yellow", ">>>", "yellow", 1);	

	my $bufs = weechat::infolist_get("buffer", "", "");
	while (weechat::infolist_next($bufs))
	{
		weechat::print("", weechat::infolist_string($bufs, "full_name"));
	}

	weechat::infolist_free($nicks);
}
