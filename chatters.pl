# -*- coding: utf-8 -*-
#
# Copyright (C) 2012 Arvydas Sidorenko <asido4@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# History:
#
#   2012-05-01, Arvydas Sidorenko <asido4@gmail.com>
#       Version 0.1: initial release
#	2012-05-11, Arvydas Sidorenko <asido4@gmail.com>
#		Version 0.2: rewritten script using bar_item to store the chatters
#		instead of nicklist_group
#

use strict;
use warnings;

my $version         = "0.2";
my $script_name     = "chatters";

# A hash with groups where the chatters are going to be added
#
# Structure:
#   "#channel1" -- "nick1" -- last msg timestamp
#               `- "nick2" -- last msg timestamp
#               `- "nick3" -- last msg timestamp
#   "#channel2" -- "nick1" -- last msg timestamp
#               `- ...
my %chatter_groups      = ();
my $chatters_bar_name   = "chatters_bar";
my $bar_frame_color     = weechat::color("red");
my $chatter_color       = weechat::color("yellow");

my $chatter_timeout = 600; # 10min (in seconds)

weechat::register($script_name, "Arvydas Sidorenko <asido4\@gmail.com>", $version, "GPL3", "Groups people into chatters and idlers", "", "");

# Close a channel
weechat::hook_signal("buffer_closing", "buffer_close_cb", "");
# Callback whenever someone leaves the channel
weechat::hook_signal("nicklist_nick_removed", "on_leave_cb", "");
# Callback whenever someone writes something in the channel
weechat::hook_signal("*,irc_in_PRIVMSG", "msg_cb", "");
# Chatter observer callback
weechat::hook_timer(60000, 0, 0, "cleanup_chatters", 0);

weechat::bar_item_new($chatters_bar_name, "chatters_bar_cb", "");

###############################################################################
# Buffer close callback
sub chatters_bar_cb
{
    # $_[0] - data
    # $_[1] - bar item
    # $_[2] - window
    my $str     = $bar_frame_color . "-- Chatters -----\n";
    my $buffer  = weechat::window_get_pointer($_[2], "buffer");
    my $channel = get_buf_channel($buffer);

    if ($channel and $chatter_groups{$channel})
    {
        foreach my $nick (keys %{ $chatter_groups{$channel} })
        {
            $str .= $chatter_color . $nick . "\n";
        }
    }

    $str .= $bar_frame_color . "-----------------\n";

    return $str;
}

###############################################################################
# Buffer close callback
sub buffer_close_cb
{
    # $_[0] - callback data (3rd hook arg)
    # $_[1] - signal (buffer_closing)
    # $_[2] - buffer pointer
    my $channel = get_buf_channel($_[2]);

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
    #    :Asido!~asido@2b600000.rev.myisp.com PRIVMSG #linux :yoo
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

    # Ignore private messages
    if ($msg =~ m/PRIVMSG (?!#)(\w+)/)
    {
        return weechat::WEECHAT_RC_OK;
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
    $channel = $tokens[2];

    $chatter_groups{$channel}{$nick} = time();
    weechat::bar_item_update($chatters_bar_name);

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
    my $channel = get_buf_channel($buf);

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

    if ($chatter_groups{$channel} and $chatter_groups{$channel}{$nick})
    {
        delete $chatter_groups{$channel}{$nick};
    }

    return weechat::WEECHAT_RC_OK;
}

###############################################################################
# Removes nicks from chatter list who idle for too long
sub cleanup_chatters
{
    
    foreach my $channel (keys %chatter_groups)
    {
        foreach my $nick (keys %{ $chatter_groups{$channel} })
        {
            if (time() - $chatter_groups{$channel}{$nick} >= $chatter_timeout)
            {
                delete $chatter_groups{$channel}{$nick};
            }
        }
    }
}

###############################################################################
# Returns the channel name of buffer
sub get_buf_channel
{
    my $buf = shift;

    return weechat::buffer_get_string($buf, "short_name");
}

###############################################################################
#
sub _log
{
    my $msg = shift;

    weechat::print("", "${script_name}: ${msg}\n");
}
