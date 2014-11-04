# Description:
#   Get information about characters
#
# Dependencies:
#   xml2js
#   moment
#   lodash
#   numeral
#
# Commands:
#   hubot add char(acter)? <eve-name> <keyID> <vCode> - Links a character to your IRC name
#   hubot set main <eve-name> - sets an added character as your main
#   hubot get main - Displays your main EVE character, if set
#   hubot get main <irc-handle> - Displays the main EVE character for IRC user <name>, if set
#   hubot get char(acter)?s - Displays all characters you have added
#   hubot get char(acter)?s <irc-handle> - Displays all characters for the IRC user
#   hubot skill queue - Displays skill queue information for your main character
#   hubot skill queue <eve-name> - Displays skill queue information for the specified characters
#   hubot skill points - Displays your main character's total SP
#   hubot skill points <eve-name> - Displays total SP for the specified character
#
# Storage:
#   eve.chars.<eve-name>:
#     <data from CharacterInfo API>
#   eve.main.<irc-handle>: <eve-name>


request = require 'request'
parser = require 'xml2json'
moment = require 'moment'
util = require 'util'
_ = require 'lodash'
numeral = require 'numeral'

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

romanNumeral = (num) ->
  return switch num
    when 1 then "I"
    when 2 then "II"
    when 3 then "III"
    when 4 then "IV"
    when 5 then "V"

getUsername = (msg) ->
  return msg.message.user.name

mainKey = (ircUserName) ->
  if ircUserName?
    key = "eve.mains.#{ircUserName.toLowerCase()}"
    return key
  else
    return null

charKey = (charName) ->
  if charName?
    key = "eve.chars.#{charName.toLowerCase()}"
    return key
  else
    return null

getMainName = (ircUserName) ->
  return robot.brain.get mainKey(ircUserName)

setMainName = (ircUserName, mainName) ->
  robot.brain.set mainKey(ircUserName), mainName.toLowerCase()

getMainChar = (ircUserName) ->
  return getChar(getMainName(ircUserName))

getChar = (charName) ->
  return robot.brain.get charKey(charName)

setChar = (charName, char) ->
  robot.brain.set charKey(charName), char

getApiErr = (json) ->
  if json.eveapi.error?
    return new Error switch json.eveapi[0].error[0].code
      when 221 then "API key does not have proper permissions"
      else json.eveapi[0].error[0].$t
  else
    return false

parseXmlBodyToJson = (body) ->
  return parser.toJson(body,{object: true, arrayNotation: true})

loadSkills = (done) ->
  opts =
    uri: "#{api}/eve/SkillTree.xml.aspx"

  request opts, (err, res, body) ->
    skillLookup = {}
    json = parseXmlBodyToJson body
    for group in json.eveapi[0].result[0].rowset[0].row
      for skill in group.rowset[0].row
        skillLookup[skill.typeID] = skill
    done()

characters = (keyID, vCode, done) ->
  opts = getBaseOpts keyID, vCode, "account/Characters"
  request opts, (err, res, body) ->
    if err
      done err, null
    else
      json = parseXmlBodyToJson body
      apiErr = getApiErr json
      if apiErr
        done apiErr
      else
        chars = {}
        for char in json.eveapi[0].result[0].rowset[0].row
          chars[char.name.toLowerCase()] = char
        done null, chars

skillQueue = (char, done) ->
  opts = getBaseOpts char.keyID, char.vCode, "char/SkillQueue"
  opts.qs.characterID = char.characterID
  request opts, (err, res, body) ->
    if err
      done err, null
    else
      json = parseXmlBodyToJson body
      apiErr = getApiErr json
      if apiErr
        done apiErr
      else
        queue = []
        for skill in json.eveapi[0].result[0].rowset[0].row
          skill.serverTime = json.eveapi.currentTime
          queue.push skill
        done null, queue

skillPoints = (char, done) ->
  opts = getBaseOpts char.keyID, char.vCode, "char/CharacterSheet"
  opts.qs.characterID = char.characterID
  request opts, (err, res, body) ->
    if err
      done err, null
    else
      json = parseXmlBodyToJson body
      apiErr = getApiErr json
      if apiErr
        done apiErr, null
      else
        sp = 0
        for rowset in json.eveapi[0].result[0].rowset
          if rowset.name == 'skills'
            for skill in rowset.row
              sp += skill.skillpoints
        done null, sp

module.exports = (robot) ->

  console.log "Loading skills..."

  loadSkills () ->

    console.log "Skills loaded"

    robot.respond /add char(acter)? (.*) (.*) (.*)/i, (msg) ->
      char = msg.match[2].toLowerCase()
      keyID = msg.match[3]
      vCode = msg.match[4]

      characters keyID, vCode, (err, chars) ->
        if err
          msg.send "Unable to retrieve characters: #{err}"
        else
          if not chars[char]
            msg.send "#{char} not found for that account"
          else
            chars[char].keyID = keyID
            chars[char].vCode = vCode
            setChar char, chars[char]
            if not getMainName(getUsername(msg))
              setMainName getUsername(msg), char
              msg.send "Added #{char} as your main character"
            else
              msg.send "Added #{char} as an additional character"

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

    robot.respond /skill points( (.*))?/i, (msg) ->
      if msg.match[2]?
        charName = msg.match[2]
      else
        user = getUsername(msg)
        charName = getMainName(user)

      char = getChar charName

      if not char?
        msg.send "I don't know about #{charName}"
      else
        skillPoints char, (err, points) ->
          nicePoints = numeral(points).format("0,0")
          msg.send "#{char.name} has #{nicePoints} SP"

    robot.respond /skill queue( (.*))?/i, (msg) ->
      if msg.match[2]?
        charName = msg.match[2]
      else
        user = getUsername(msg)
        charName = getMainName(user)

      char = getChar charName

      if not char?
        msg.send "I don't know about #{charName}"
      else
        skillQueue char, (err, queue) ->
          if err
            msg.send "Unable to get skill queue: #{err}"
          else
            count = queue.length
            firstSkill = queue[0]
            lastSkill = queue[count - 1]

            serverMoment = moment(lastSkill.serverTime)
            firstMoment = moment(firstSkill.endTime)
            lastMoment = moment(lastSkill.endTime)

            queueEndsIn = lastMoment.from(serverMoment, true)
            firstEndsIn = firstMoment.from(serverMoment, true)
            firstName = skillLookup[firstSkill.typeID].typeName
            firstLevel = romanNumeral firstSkill.level

            if count == 0
              out = "Uh oh! #{char.name} does not have any skills in queue!  LOG IN AND FIX IT!"
            else
              out = "#{char.name} is currently training #{firstName} #{firstLevel} which will finish in #{firstEndsIn}."
              if count > 1
                out += " #{char.name}'s queue has #{count - 1} additional skill#{if count - 1 == 1 then "" else "s"} which finishes in #{queueEndsIn}."
              else
                out += " There are no other skills in the queue."

            msg.send out


