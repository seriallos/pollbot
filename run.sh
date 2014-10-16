#!/bin/bash

export PORT=8082

export REDIS_URL=redis://localhost:6379/pollbot

export HUBOT_IRC_SERVER=irc.coldfront.net
export HUBOT_IRC_ROOMS=#adhocracy
export HUBOT_IRC_NICK=PollBot
export HUBOT_IRC_UNFLOOD=true

npm install

bin/hubot -a irc --name PollBot
