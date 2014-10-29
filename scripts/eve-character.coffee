# Description:
#   Get information about characters
#
# Dependencies:
#   xml2js
#   moment
#
# Commands:
#   hubot set main <name> <keyID> <vCode> - Allows you to track this character
#   hubot get main - Displays your main EVE character, if set
#   hubot get main <name> - Displays the main EVE character for IRC user <name>, if set


request = require 'request'
parser = require 'xml2json'
moment = require 'moment'
util = require 'util'

api = "https://api.eveonline.com"
skillLookup = {}

dd = (obj) ->
  console.log util.inspect(obj,{depth:null})


getBaseOpts = (keyID, vCode, path) ->
  opts =
    uri: "#{api}/#{path}.xml.aspx"
    qs:
      keyID: keyID
      vCode: vCode
  return opts

charKey = (user) ->
  key = "#{user}.eve.char"
  return key

getUsername = (msg) ->
  return msg.message.user.name

getMainChar = (user) ->
  return robot.brain.get charKey(user)

loadSkills = () ->
  console.log "Loading skills"
  opts =
    uri: "#{api}/eve/SkillTree.xml.aspx"

  request opts, (err, res, body) ->
    skillLookup = {}
    json = parser.toJson(body,{object:true})
    for group in json.eveapi.result.rowset.row
      for skill in group.rowset.row
        skillLookup[skill.typeID] = skill
    console.log "Skills loaded"

loadSkills()

characters = (keyID, vCode, done) ->
  opts = getBaseOpts keyID, vCode, "account/Characters"
  request opts, (err, res, body) ->
    json = parser.toJson(body,{object: true})
    chars = {}
    for char in json.eveapi.result.rowset.row
      chars[char.name] = char
    done chars

skillQueue = (char, done) ->
  opts = getBaseOpts char.keyID, char.vCode, "char/SkillQueue"
  opts.qs.characterID = char.characterID
  request opts, (err, res, body) ->
    json = parser.toJson(body,{object:true})
    queue = []
    for skill in json.eveapi.result.rowset.row
      skill.serverTime = json.eveapi.currentTime
      queue.push skill
    done queue

module.exports = (robot) ->

  robot.respond /set main (.*) (.*) (.*)/i, (msg) ->
    char = msg.match[1]
    keyID = msg.match[2]
    vCode = msg.match[3]

    characters keyID, vCode, (chars) ->
      if not chars[char]
        msg.send "#{char} not found for that account"
      else
        chars[char].keyID = keyID
        chars[char].vCode = vCode
        robot.brain.set charKey(getUsername(msg)), chars[char]
        msg.send "Saved #{char} as your main character"

  robot.respond /get main( (.*))?$/i, (msg) ->
    if msg.match[2]?
      user = msg.match[2]
    else
      user = getUsername(msg)

    char = getMainChar(user)
    if char?
      msg.send "#{user}'s main character is #{char.name} in #{char.corporationName}."
    else
      msg.send "#{user} does not have a main character set.  Look at 'set main' help"

  robot.respond /skill queue( (.*))?/i, (msg) ->
    if msg.match[2]?
      user = msg.match[2]
    else
      user = getUsername(msg)

    char = getMainChar(user)

    if not char?
      msg.send "No main character found for #{user}"
    else
      skillQueue char, (queue) ->
        out = ""
        for skill in queue
          end = moment(skill.endTime)
          serverTime = moment(skill.serverTime)
          endsIn = end.from(serverTime)
          name = skillLookup[skill.typeID].typeName
          level = switch skill.level
            when 1 then "I"
            when 2 then "II"
            when 3 then "III"
            when 4 then "IV"
            when 5 then "V"
          out += "#{name} #{level} finishes #{endsIn}\n"
        msg.send out


