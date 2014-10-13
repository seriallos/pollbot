#!/bin/bash

export HUBOT_IRC_SERVER=irc.coldfront.net
export HUBOT_IRC_ROOMS=#adhocracy
export HUBOT_IRC_NICK=PollBot
export HUBOT_IRC_UNFLOOD=true

bin/hubot -a irc --name PollBot
