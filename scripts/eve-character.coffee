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
#   hubot set main <name> <keyID> <vCode> - Allows you to track this character
#   hubot get main - Displays your main EVE character, if set
#   hubot get main <name> - Displays the main EVE character for IRC user <name>, if set


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

typeIsArray = Array.isArray || ( value ) -> return {}.toString.call( value ) is '[object Array]'

romanNumeral = (num) ->
  return switch num
    when 1 then "I"
    when 2 then "II"
    when 3 then "III"
    when 4 then "IV"
    when 5 then "V"

charKey = (user) ->
  key = "#{user}.eve.char"
  return key

getUsername = (msg) ->
  return msg.message.user.name

getMainChar = (user) ->
  return robot.brain.get charKey(user)

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
          chars[char.name] = char
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
        for skill in json.eveapi[0].result[0].rowset[0].row
          sp += skill.skillpoints
        done null, sp

module.exports = (robot) ->

  console.log "Loading skills..."

  loadSkills () ->

    console.log "Skills loaded"

    robot.respond /set main (.*) (.*) (.*)/i, (msg) ->
      char = msg.match[1]
      keyID = msg.match[2]
      vCode = msg.match[3]

      characters keyID, vCode, (err, chars) ->
        if err
          msg.send "Unable to retrieve characters: #{err}"
        else
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

    robot.respond /skill points( (.*))?/i, (msg) ->
      if msg.match[2]?
        user = msg.match[2]
      else
        user = getUsername(msg)

      char = getMainChar(user)

      if not char?
        msg.send "No main character found for #{user}. Look at 'set main' help"
      else
        skillPoints char, (err, points) ->
          nicePoints = numeral(points).format("0,0")
          msg.send "#{char.name} has #{nicePoints} SP"

    robot.respond /skill queue( (.*))?/i, (msg) ->
      if msg.match[2]?
        user = msg.match[2]
      else
        user = getUsername(msg)

      char = getMainChar(user)

      if not char?
        msg.send "No main character found for #{user}. Look at 'set main' help"
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


