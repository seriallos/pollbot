# Description:
#   Get information about characters
#
# Dependencies:
#   xml2js
#   moment
#   lodash
#   numeral
#   js-yaml
#   async
#
# Storage:
#   eve.chars.<eve-name>:
#     keyID
#     vCode
#     ...fields from character API
#   eve.main.<irc-handle>: <eve-name>
#   eve.corp.<irc-handle>:
#     keyID
#     vCode
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
#   hubot corp key <keyID> <vCode> - Link a corp to your IRC name
#   hubot towers - Reports fuel and stront status for corp POSes
#   hubot pos inventory <item name> - Reports quantity of <item name> in your corp POSes

fs = require 'fs'
util = require 'util'

request = require 'request'
parser = require 'xml2json'
moment = require 'moment'
_ = require 'lodash'
numeral = require 'numeral'
yaml = require 'js-yaml'
async = require 'async'

api = "https://api.eveonline.com"
skillLookup = {}

gLocations = {}
gTypes = {}

try
  console.log "Loading Types"
  gTypes = yaml.safeLoad(fs.readFileSync('./types.yaml'))
  console.log "Types loaded"

  gTypeNameToId = _.invert gTypes

  console.log "Loading Locations"
  gLocations = yaml.safeLoad(fs.readFileSync('./locations.yaml'))
  console.log "Locations loaded"
catch e
  console.log e
  process.exit 2

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

corpKey = (ircUserName) ->
  if ircUserName?
    key = "eve.corp.#{ircUserName.toLowerCase()}"
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

getCorpApiKey = (ircUserName) ->
  return robot.brain.get corpKey(ircUserName)

setCorpApiKey = (ircUserName, keyID, vCode) ->
  key = corpKey(ircUserName)
  data =
    keyID: keyID
    vCode: vCode
  robot.brain.set key, data

getApiErr = (json) ->
  if json.eveapi[0].error?
    return new Error switch json.eveapi[0].error[0].code
      when 221 then "API key does not have proper permissions"
      else json.eveapi[0].error[0].$t
  else
    return false

parseXmlBodyToJson = (body) ->
  return parser.toJson(body,{object: true, arrayNotation: true})

requestAndJsonify = (opts, done) ->
  if not opts.headers?
    opts.headers = {}
  opts.headers['User-Agent'] = 'Hubot Plugin by Bellatroix - sollaires@gmail.com (nodejs:request)'
  request opts, (err, res, body) ->
    if err
      done err, null
    else
      json = parseXmlBodyToJson body
      apiErr = getApiErr json
      if apiErr
        done apiErr
      else
        done null, json

loadSkills = (done) ->
  opts =
    uri: "#{api}/eve/SkillTree.xml.aspx"

  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      skillLookup = {}
      for group in json.eveapi[0].result[0].rowset[0].row
        for skill in group.rowset[0].row
          skillLookup[skill.typeID] = skill
      done()

characters = (keyID, vCode, done) ->
  opts = getBaseOpts keyID, vCode, "account/Characters"
  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      chars = {}
      for char in json.eveapi[0].result[0].rowset[0].row
        chars[char.name.toLowerCase()] = char
      done null, chars

skillQueue = (char, done) ->
  opts = getBaseOpts char.keyID, char.vCode, "char/SkillQueue"
  opts.qs.characterID = char.characterID
  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      queue = []
      for skill in json.eveapi[0].result[0].rowset[0].row
        skill.serverTime = json.eveapi.currentTime
        queue.push skill
      done null, queue

skillPoints = (char, done) ->
  opts = getBaseOpts char.keyID, char.vCode, "char/CharacterSheet"
  opts.qs.characterID = char.characterID
  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      sp = 0
      for rowset in json.eveapi[0].result[0].rowset
        if rowset.name == 'skills'
          for skill in rowset.row
            sp += skill.skillpoints
      done null, sp

corpItemLocation = (corp, itemIds, done) ->
  opts = getBaseOpts corp.keyID, corp.vCode, "corp/Locations"
  if not _.isArray itemIds
    itemIds = [itemIds]
  opts.qs.IDs = itemIds.join(',')
  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      itemNames = {}
      for item in json.eveapi[0].result[0].rowset[0].row
        itemNames[item.itemID] = item.itemName
      done null, itemNames

posStateName = (posState) ->
  return switch posState
    when 0 then "Unanchored"
    when 1 then "Anchored"
    when 2 then "Onlining"
    when 3 then "Reinforced"
    when 4 then "Online"

posList = (corp, done) ->
  opts = getBaseOpts corp.keyID, corp.vCode, "corp/StarbaseList"
  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      towers = {}
      funcs = []
      for tower in json.eveapi[0].result[0].rowset[0].row
        towerInfo =
          typeId: tower.typeID
          locationId: tower.locationID
          moonId: tower.moonID
          stateId: tower.state
          stateName: posStateName(tower.state)
        towers[tower.itemID] = towerInfo
        tmp = (id, typeId) ->
          funcs.push (cb) ->
            posDetail corp, id, typeId, cb
        tmp(tower.itemID, tower.typeID)

      async.parallel(
        funcs,
        (err, results) ->
          if err
            done err, null
          else
            for tower in results
              towers[tower.itemId] = _.merge towers[tower.itemId], tower
            corpItemLocation corp, _.keys(towers), (err, towerNames) ->
              for towerId, towerName of towerNames
                towers[towerId].name = towerName
              done null, towers
      )

towerAttributes = (towerTypeId) ->
  stats =
    smallNormal:
      strontMax: 12500
      fuelMax: 35000
      fuelPerHour: 10
      strontPerHour: 100
    smallFaction:
      strontMax: 12500
      fuelMax: 35000
      fuelPerHour: 9
      strontPerHour: 100
    smallFactionRare:
      strontMax: 12500
      fuelMax: 35000
      fuelPerHour: 8
      strontPerHour: 100
    mediumNormal:
      strontMax: 25000
      fuelMax: 70000
      fuelPerHour: 20
      strontPerHour: 200
    mediumFaction:
      strontMax: 25000
      fuelMax: 70000
      fuelPerHour: 18
      strontPerHour: 200
    mediumFactionRare:
      strontMax: 25000
      fuelMax: 70000
      fuelPerHour: 16
      strontPerHour: 200
    largeNormal:
      strontMax: 50000
      fuelMax: 140000
      fuelPerHour: 40
      strontPerHour: 400
    largeFaction:
      strontMax: 50000
      fuelMax: 140000
      fuelPerHour: 36
      strontPerHour: 400
    largeFactionRare:
      strontMax: 50000
      fuelMax: 140000
      fuelPerHour: 32
      strontPerHour: 400

  prefixes =
    Normal: [
      'Amarr'
      'Caldari'
      'Gallente'
      'Minmatar'
    ]
    Faction: [
      'Blood'
      'Sansha'
      'Guristas'
      'Serpentis'
      'Angel'
    ]
    FactionRare: [
      'Dark Blood'
      'True Sansha'
      'Dread Guristas'
      'Shadow'
      'Domination'
    ]
  sizeMap =
    'small': ' Small'
    'medium': ' Medium'
    'large': ''
  towerMap = {}
  for type, types of prefixes
    for prefix in types
      for size, suffix of sizeMap
        name = "#{prefix} Control Tower#{suffix}"
        towerMap[name] = "#{size}#{type}"

  towerType = towerMap[gTypes[towerTypeId]]
  return stats[towerType]

posDetail = (corp, towerId, towerType, done) ->
  opts = getBaseOpts corp.keyID, corp.vCode, "corp/StarbaseDetail"
  opts.qs.itemId = towerId
  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      towerDetail =
        itemId: towerId

      fuels = json.eveapi[0].result[0].rowset[0].row
      for fuel in fuels
        if gTypes[fuel.typeID] == 'Strontium Clathrates'
          strontSize = 3
          towerDetail.stront = fuel.quantity
          towerDetail.strontSize = fuel.quantity * strontSize
        else
          fuelSize = 5
          towerDetail.curFuel = fuel.quantity
          towerDetail.curFuelSize = fuel.quantity * fuelSize

      towerDetail = _.merge towerDetail, towerAttributes(towerType)

      towerDetail.fuelHours = towerDetail.curFuel / towerDetail.fuelPerHour
      towerDetail.strontHours = towerDetail.stront / towerDetail.strontPerHour
      towerDetail.fuelPct = 100 * (towerDetail.curFuelSize / towerDetail.fuelMax)
      towerDetail.strontPct = 100 * (towerDetail.strontSize / towerDetail.strontMax)

      done null, towerDetail

corpAssetList = (corp, done) ->
  opts = getBaseOpts corp.keyID, corp.vCode, "corp/AssetList"
  requestAndJsonify opts, (err, json) ->
    if err then done err
    else
      interestingContainers = [
        'Corporate Hangar Array'
        'Ship Maintenance Array'
        'Personal Hangar Array'
      ]
      inventory = {}
      for row in json.eveapi[0].result[0].rowset[0].row
        locationId = row.locationID
        containerTypeId = row.typeID
        if gTypes[containerTypeId] in interestingContainers
          for item in row.rowset[0].row
            if inventory[item.typeID]?
              inventory[item.typeID] += item.quantity
            else
              inventory[item.typeID] = item.quantity
      done null, inventory

corpAssetSearch = (corp, itemId, done) ->
  corpAssetList corp, (err, inventory) ->
    if err then done err
    else
      done null, inventory[itemId] || 0

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

    robot.respond /corp key (.*) (.*)/i, (msg) ->
      username = getUsername msg
      keyID = msg.match[1]
      vCode = msg.match[2]
      setCorpApiKey username, keyID, vCode
      msg.send "Corp key set for #{username}"

    robot.respond /towers/i, (msg) ->
      corp = getCorpApiKey(getUsername(msg))

      if not corp?
        msg.send "You don't have a corp API key set up"
      else
        posList corp, (err, towers) ->
          if err
            msg.send "Unable to get tower list: #{err}"
          else
            for towerId, tower of towers
              fuelDuration = moment.duration(tower.fuelHours, 'hours')
              out = "#{gLocations[tower.moonId]}: #{tower.name} (#{gTypes[tower.typeId]}) is #{tower.stateName}."
              if tower.stateName == 'Online'
                out += "  It has enough fuel for #{fuelDuration.humanize()} and stront for #{Math.round(tower.strontHours)} hours."
              msg.send out

    robot.respond /test corp assets/i, (msg) ->
      corp = getCorpApiKey(getUsername(msg))

      if not corp?
        msg.send "You don't have a corp API key set up"
      else
        corpAssetList corp, (err, assets) ->
          msg.send "Testing corp assets - data in console"

    robot.respond /pos inventory (.*)/i, (msg) ->
      itemName = msg.match[1]
      corp = getCorpApiKey(getUsername(msg))

      if not corp?
        msg.send "You don't have a corp API key set up"
      else
        itemId = gTypeNameToId[itemName]
        corpAssetSearch corp, itemId, (err, quantity) ->
          if err then msg.send "Error: #{err}"
          else
            msg.send "#{itemName}: #{quantity}"
