use strict;
use warnings;

my $version         = "0.1";
my $script_name     = "chatters";
# The array with groups where the chatters are going to be added
my %chatter_groups  = ();

my $chatter_timeout = 600; # 10min (in seconds)

weechat::register($script_name, "Arvydas Sidorenko <asido4\@gmail.com>", $version, "GPL2", "Groups people into chatters and idlers", "", "");

# Callback whenever you join a channel
weechat::hook_signal("irc_channel_opened", "channel_joined_cb", "");
# Close a channel
weechat::hook_signal("buffer_closing", "buffer_close_cb", "");
# Callback whenever someone leaves the channel
weechat::hook_signal("nicklist_nick_removed", "on_leave_cb", "");
# Callback whenever someone writes something in the channel
weechat::hook_signal("*,irc_in_PRIVMSG", "msg_cb", "");
# Chatter observer callback
weechat::hook_timer(60000, 0, 0, "cleanup_chatters", 0);

###############################################################################
# Channel join callback
sub channel_joined_cb
{
    # $_[0] - callback data (3rd hook arg)
    # $_[1] - signal (irc_channel_opened)
    # $_[2] - buffer pointer
    my $buffer = $_[2];

    create_chatter_group($buffer);
    return weechat::WEECHAT_RC_OK;
}

###############################################################################
# Buffer close callback
sub buffer_close_cb
{
    # $_[0] - callback data (3rd hook arg)
    # $_[1] - signal (buffer_closing)
    # $_[2] - buffer pointer
    my $channel = buf_to_channel($_[2]);

    if ($chatter_groups{$channel})
    {
        delete $chatter_groups{$channel};
    }
}

###############################################################################
# Gets called when someones writes in a channel
sub msg_cb
{
    # $_[0] - callback data (3rd hook arg)
    # $_[1] - event name
    # $_[2] - the message:
    #	 :Asido!~asido@2b600000.rev.myisp.com PRIVMSG #linux :yoo
    my $msg     = $_[2];
    my $nick    = "";
    my $channel = "";
    my @tokens  = ();
    my $chatter;

    unless (defined($msg))
    {
        _log("message arrived empty. line: " . __LINE__);
        return weechat::WEECHAT_RC_ERROR;
    }

    @tokens = split(/ /, $msg);
    if (@tokens == 0)
    {
        _log("feels like corrupted message. line: " . __LINE__);
        return weechat::WEECHAT_RC_ERROR;
    }

    $nick = $tokens[0];
    $nick =~ m/:(.*)!/;
    $nick = $1;
    $channel = channel_to_key($tokens[2]);
    
    unless ($chatter_groups{$channel})
    {
        $chatter_groups{$channel}{'group'} = weechat::nicklist_add_group($channel, "", $channel, "red", "1");
    }
    
    $chatter = get_chatter($chatter_groups{$channel}, $nick);
    if ($chatter)
    {
        refresh_chatter($chatter_groups{$channel}, $nick);
    }
    else
    {
        add_chatter($chatter_groups{$channel}, $nick);
    }

    return weechat::WEECHAT_RC_OK;
}

###############################################################################
# Gets called when someones leaves a channel
sub on_leave_cb
{
    # $_[0] - unknown (weechat::print prints nothing)
    # $_[1] - event name (nicklist_nick_removed)
    # $_[2] - 0x1ffda70,spoty (<buffer_pointer>,<nick>
    my $buf     = $_[2];
    my $nick    = $_[2];
    my $channel = buf_to_channel($buf);

    # Extract buffer pointer
    if ($buf =~ m/(.*),/)
    {
        $buf = $1;
    }
    else
    {
        _log("couldn't extract buffer pointer. line: " . __LINE__);
        return weechat::WEECHAT_RC_ERROR;
    }
    
    # Extract nick
    if ($nick =~ m/.*,(.*)/)
    {
        $nick = $1;
    }
    else
    {
        _log("couldn't extract nick. line: " . __LINE__);
        return weechat::WEECHAT_RC_ERROR;
    }

    # If the script was loaded after joining a channel, the group is not yet created
    # TODO: should create one?
    if ($chatter_groups{$channel})
    {
        my $chatter = get_chatter($chatter_groups{$channel}, $nick);
        if ($chatter)
        {
            remove_chatter($chatter_groups{$channel}, $chatter);
            delete $chatter_groups{$channel}{'nicks'}{$nick};
        }
    }

    return weechat::WEECHAT_RC_OK;
}

###############################################################################
#
sub cleanup_chatters
{
    foreach my $channel (keys %chatter_groups)
    {
        foreach my $nick (keys %{ $chatter_groups{$channel}{'nicks'} })
        {
            if (time() - $chatter_groups{$channel}{'nicks'}{$nick}{'last_msg_time'} >= $chatter_timeout)
            {
                my $chatter = get_chatter($chatter_groups{$channel}, $nick);
                remove_chatter($chatter_groups{$channel}, $chatter);
                delete $chatter_groups{$channel}{'nicks'}{$nick};
            }
        }
    }
}

###############################################################################
#
sub create_chatter_group
{
    my $buf  	= shift;
    my $channel = "";

    unless ($buf)
    {
        _log("no buffer provided. line: " . __LINE__);
        return;
    }

    $channel = buf_to_channel($buf);

    unless ($chatter_groups{$channel})
    {
        $chatter_groups{$channel}{'buffer'} = $buf;
        $chatter_groups{$channel}{'group'} = weechat::nicklist_add_group($buf, "", channel_to_groupname($channel), "red", "1");
        unless ($chatter_groups{$channel})
        {
            _log("failed to create a group for channel '${channel}'. line: " . __LINE__);
        }
    }
}

###############################################################################
# Adds a nick to chatters list
sub add_chatter
{
    my $channel = shift;
    my $nick 	= shift;

    $channel->{'nicks'}{$nick}{'last_msg_time'} = time();
    # Prepend a space or add will fail since the nick is already in the root nicklist
    $nick = " " . $nick;

    unless (weechat::nicklist_add_nick($channel->{'buffer'}, $channel->{'group'}, $nick, "yellow", ">>", "red", 1))
    {
        _log("failed to add nick to nicklist. line: " . __LINE__);
    }
}

###############################################################################
#
sub refresh_chatter
{
    my $channel = shift;
    my $nick    = shift;

    $channel->{'nicks'}{$nick}{'last_msg_time'} = time();
}

###############################################################################
#
sub remove_chatter
{
    my $channel = shift;
    my $nick    = shift; # This is not string but an object

    weechat::nicklist_remove_nick($channel->{'buffer'}, $nick);
}

###############################################################################
#
sub get_chatter
{
    my $channel = shift;
    my $nick    = shift;

    return weechat::nicklist_search_nick($channel->{'buffer'}, $channel->{'group'}, " ".$nick);
}

###############################################################################
#
sub buf_to_channel
{
    my $buf 	= shift;
    my $channel = "";

    $channel = weechat::buffer_get_string($buf, "short_name");
    return channel_to_key($channel);
}

###############################################################################
# Process the channel name to use as a key
sub channel_to_key
{
    my $channel = shift;

    $channel =~ s/^#+//;
    return $channel;
}

###############################################################################
# Appends piped zero so that the group would appear the first in nicklist
sub channel_to_groupname
{
    my $channel = shift;
    return "%|".$channel;
}

###############################################################################
#
sub _log
{
    my $msg = shift;

    weechat::print("", "${script_name}: ${msg}\n");
}
