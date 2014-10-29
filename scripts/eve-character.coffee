# Description:
#   Get information about characters
#
# Dependencies:
#   xml2js
#
# Commands:
#   hubot set main <name> <keyID> <vCode> - Allows you to track this character


request = require 'request'
parser = require 'xml2json'
util = require 'util'

dd = (obj) ->
  console.log util.inspect(obj,{depth:null})

api = "https://api.eveonline.com"

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

characters = (keyID, vCode, done) ->
  opts = getBaseOpts keyID, vCode, "account/Characters"
  request opts, (err, res, body) ->
    json = parser.toJson(body,{object: true})
    chars = {}
    for char in json.eveapi.result.rowset.row
      chars[char.name] = char
    done chars


module.exports = (robot) ->

  robot.respond /set main (.*) (.*) (.*)/i, (msg) ->
    char = msg.match[1]
    keyID = msg.match[2]
    vCode = msg.match[3]

    console.log msg

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

    char = robot.brain.get charKey(user)
    if char?
      msg.send "#{user}'s main character is #{char.name} in #{char.corporationName}."
    else
      msg.send "#{user} does not have a main character set.  Look at 'set char' help"
