#!/bin/perl

eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell

=begin COPYRIGHT

   mcabber-event.pl - advanced event handling for mcabber
   Copyright (C) 2016 Benjamin Abendroth

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.

=end COPYRIGHT

=cut

use strict;
use warnings;

use Env qw(HOME USER);
use Config::General qw(ParseConfig);
use Text::ParseWords qw(shellwords);

# Because this script is only called by mcabber
# we have to redirect our output to a logfile.
open(my $log_fh, '>>', "/tmp/mcabber-event-$USER.log");
*STDERR = $log_fh;
*STDOUT = $log_fh;

my %cfg = ParseConfig(
   -ConfigFile => "$HOME/.mcabber/mcabber-event.rc",
   -InterPolateEnv => 1,
   -InterPolateVars => 1,
);

# Events are handled using the functions in this dispatch table:
#  { <event name> => <anonymous function> }
my %EVENTS;

# The MSG-event is split up into the events MSG:IN, MSG:OUT and MSG:MUC
$EVENTS{MSG} = sub
{
   my ($sub_event, @args) = @_;
   $EVENTS{"MSG:$sub_event"}->(@args);
};

# Simple incoming message
$EVENTS{"MSG:IN"} = sub
{
   my ($user, $file) = @_;
   my $msg = read_file($file);

   parse_urls($msg);
   call_rule('message:in', {user=>$user, file=>$file, message=>$msg});
   unlink($file);
};

# Simple outgoing message
$EVENTS{"MSG:OUT"} = sub
{
   my ($to_buddy) = @_;
   call_rule('message:out', {user=>$to_buddy});
};

# MUC-message handling
$EVENTS{"MSG:MUC"} = sub
{
   my ($room_jid, $file) = @_;
   my ($room_name, $room_server) = split('@', $room_jid, 2);

   my $msg = read_file($file);
   (my $room_user, $msg) = $msg =~ /<(.+)> (.*)/;

   parse_urls($msg);

   my $call_placeholders = {
      message  => $msg,
      file     => $file,
      user     => $room_user,
      server   => $room_server,
      room     => $room_name
   };

   # If own message, call message:muc:out and leave
   for my $nick (ref2array($cfg{nick})) {
      if ($nick eq $room_user) {
         return unlink($file) if call_rule('message:muc:out', $call_placeholders);
      }
   }

   # If message contains highlight keywords, call message:muc:highlight and leave
   for my $keyword (ref2array($cfg{highlight})) {
      if ($msg =~ m/\Q$keyword\E/) {
         return unlink($file) if call_rule('message:muc:highlight', $call_placeholders);
      }
   }

   # Simple muc message
   call_rule('message:muc:in', $call_placeholders);
   unlink($file);
};

# Called when buddy in roster changes status
$EVENTS{STATUS} = sub
{
   my ($status, $user) = @_;

   my $long_status = {
      _ => 'offline',
      A => 'away',
      D => 'do_not_disturb',
      F => 'free',
      O => 'online',
      N => 'not_available'
   }->{$status};

   call_rule("status:$long_status", {user=>$user});
};

# Called when number of unread messages changes
$EVENTS{UNREAD} = sub
{
   my ($unread) = @_;

   my $vars = {};
   (
      $vars->{unread_buffers},
      $vars->{unread_buffers_attention_sign},
      $vars->{unread_muc_buffers},
      $vars->{unread_muc_buffers_attention_sign}
   ) = split(/ /, $unread);

   call_rule('unread', $vars);
};

# # # Main # # #
my $event   = shift @ARGV     || die "This script should only be called by mcabber\n";
my $handler = $EVENTS{$event} || die "No handler for event '$event' found\n";
$handler->(@ARGV);

# # # Functions # # #
sub ref2array {
   my $array_ref = shift || return ();
   return @$array_ref if ref $array_ref eq 'ARRAY';
   return ($array_ref);
}

sub call_rule {
   my ($rule_name, $variables) = @_;

   return 0 if not exists $cfg{$rule_name};

   for my $exec (ref2array($cfg{$rule_name}{exec})) {
      my @argv = shellwords($exec);

      for my $arg (@argv) {
         $arg =~ s/%$_%/$variables->{$_}/g for (keys %$variables);
      }

      eval { system(@argv) };
   }

   return 1;
}

sub read_file {
   open(my $fh, '<', $_[0]) or warn "$_[0]: $!";
   return <$fh>;
}

sub parse_urls {
   my ($msg) = @_;

   while ($msg =~ m<((((http|ftp)s?://)|www[.][-a-z0-9.]+|(mailto:|news:))(%[0-9A-F]{2}|[-_.!~*';/?:@&=+\$,#[:alnum:]])+)>g) {
      call_rule('url', {url=>$&});
   }
}
