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
#   eve.inventoryAmount.<corpId>
#   eve.corp.<irc-handle>:
#     keyID
#     vCode
#     corpId
#     corpName
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
#   hubot pos expect <num> <item> - Sets expected amount of item in your POS
#   hubot pos expected <item> - Gets current expected amount for <item>
#   hubot pos shopping list - Returns list of items needed to fulfill expected inventory amounts

fs = require 'fs'
util = require 'util'
querystring = require 'querystring'

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

module.exports = (robot) ->

  dlog = (msg) ->
    console.log ":: #{msg}"

  dd = (obj) ->
    dlog util.inspect(obj,{depth:null})


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

  invAmountKey = (corpId) ->
    if corpId?
      return "eve.inventoryAmount.#{corpId}"
    else
      return null

  apiCacheKey = (key) ->
    return "apiCache.#{key}"

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

  getCorpData = (ircUserName) ->
    return robot.brain.get corpKey(ircUserName)

  setCorpData = (ircUserName, keyID, vCode, corpId, corpName) ->
    key = corpKey(ircUserName)
    data =
      keyID: keyID
      vCode: vCode
      id: corpId
      name: corpName
    robot.brain.set key, data

  getInventoryAmounts = (corpId) ->
    return robot.brain.get invAmountKey(corpId)

  getInventoryAmount = (corpId, itemId) ->
    amounts = getInventoryAmounts(corpId)
    if amounts[itemId]?
      return amounts[itemId]
    else
      return null

  setInventoryAmounts = (corpId, amounts) ->
    key = invAmountKey corpId
    robot.brain.set key, amounts

  setInventoryAmount = (corpId, itemId, amount) ->
    amounts = getInventoryAmounts corpId
    if not amounts?
      amounts = {}
    amounts[itemId] = amount
    setInventoryAmounts corpId, amounts

  getApiErr = (json) ->
    if json.eveapi[0].error?
      return new Error switch json.eveapi[0].error[0].code
        when 221 then "API key does not have proper permissions"
        else json.eveapi[0].error[0].$t
    else
      return false

  itemSearch = (items, itemSearch) ->
    results = []
    re = new RegExp(".*#{itemSearch}.*",'i')
    for itemId, itemName of items
      itemInfo =
        itemId: itemId
        itemName: itemName
      # exact match, go ahead and return it
      if itemName.toLowerCase() == itemSearch.toLowerCase()
        return [ itemInfo ]
      if itemName.match re
        results.push { itemId: itemId, itemName: itemName }
    return results

  parseXmlBodyToJson = (body) ->
    return parser.toJson(body,{object: true, arrayNotation: true})

  requestAndJsonify = (opts, done) ->
    if not opts.headers?
      opts.headers = {}
    opts.headers['User-Agent'] = 'Hubot Plugin by Bellatroix - sollaires@gmail.com (nodejs:request)'

    opts._useCache ?= true

    cacheKey = opts.uri + "?" + querystring.stringify(opts.qs)
    if opts._useCache
      brainCacheKey = apiCacheKey cacheKey

      cacheData = robot.brain.get brainCacheKey

      nowMomentUnix = moment().format('X')

      if cacheData? and cacheData.cacheUntil > nowMomentUnix
        remainingTime = cacheData.cacheUntil - nowMomentUnix
        cacheExpire = moment().add(remainingTime*1000)
        duration = moment.duration(cacheExpire,'minutes')
        dlog "CACHE HIT - valid until #{cacheExpire.format()} (#{duration.humanize()})"
        done null, cacheData.data
        return

      dlog "CACHE MISS - fetching #{cacheKey}"
    else
      dlog "Cache explicitly turned off for #{cacheKey}"

    request opts, (err, res, body) ->
      if err
        done err, null
      else
        json = parseXmlBodyToJson body
        apiErr = getApiErr json
        if apiErr
          done apiErr
        else
          now = moment(json.eveapi[0].currentTime[0])
          cacheUntil = moment(json.eveapi[0].cachedUntil[0])
          diff = cacheUntil.diff(now)

          cacheData =
            data: json
            cacheUntil: moment().add(diff).format('X')
          robot.brain.set brainCacheKey, cacheData
          done null, cacheData.data

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

  notifications = (char, done) ->
    opts = getBaseOpts char.keyID, char.vCode, "char/Notifications"
    opts.qs.characterID = char.characterID
    opts._useCache = false
    requestAndJsonify opts, (err, json) ->
      if err then done err
      else
        done json.eveapi[0].result[0].rowset[0].row

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

  corpSheet = (corp, done) ->
    opts = getBaseOpts corp.keyID, corp.vCode, "corp/CorporationSheet"
    requestAndJsonify opts, (err, json) ->
      data = {}
      data.id = json.eveapi[0].result[0].corporationID
      data.name = json.eveapi[0].result[0].corporationName
      data.ticket = json.eveapi[0].result[0].ticker
      done null, data

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

  corpReactionAssets = (corp, done) ->
    opts = getBaseOpts corp.keyID, corp.vCode, "corp/AssetList"
    requestAndJsonify opts, (err, json) ->
      if err then done err
      else
        interestingContainers = [
          'Hybrid Polymer Silo',
          'Biochemical Silo',
          'Silo',
          'Polymer Reactor Array',
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

  corpAssetSearch = (corp, itemIds, done) ->
    corpAssetList corp, (err, inventory) ->
      if err then done err
      else
        results = {}
        for id in itemIds
          results[id] = inventory[id] || 0
        done null, results

  async.parallel(
    [
      (cb) ->
        dlog "Loading Types"
        fs.readFile './types.yaml', (err, data) ->
          gTypes = yaml.safeLoad(data)
          dlog "Types loaded"
          gTypeNameToId = _.invert gTypes
          cb()
      (cb) ->
        dlog "Loading Locations"
        fs.readFile './locations.yaml', (err, data) ->
          gLocations = yaml.safeLoad(data)
          dlog "Locations loaded"
          cb()
      (cb) ->
        dlog "Loading skills"
        loadSkills () ->
          dlog "Skills loaded"
          cb()
    ],
    (err, results) ->
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
        corp = {}
        corp.keyID = msg.match[1]
        corp.vCode = msg.match[2]
        corpSheet corp, (err, corpData) ->
          setCorpData username, corp.keyID, corp.vCode, corpData.id, corpData.name
          msg.send "Corp key set for #{username}"

      robot.respond /towers/i, (msg) ->
        corp = getCorpData(getUsername(msg))

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
                  out += "  It has enough fuel for #{fuelDuration.humanize()} (#{Math.round(tower.fuelPct)}% full) and stront for #{Math.round(tower.strontHours)} hours."
                msg.send out

      robot.respond /test corp assets/i, (msg) ->
        corp = getCorpData(getUsername(msg))

        if not corp?
          msg.send "You don't have a corp API key set up"
        else
          corpAssetList corp, (err, assets) ->
            msg.send "Testing corp assets - data in console"

      robot.respond /pos inventory (.*)/i, (msg) ->
        itemName = msg.match[1]
        corp = getCorpData(getUsername(msg))

        if not corp?
          msg.send "You don't have a corp API key set up"
        else
          maxResults = 10
          items = itemSearch gTypes, itemName
          if items.length == 0
            msg.send "No market item found for '#{itemName}'"
          else if items.length <= maxResults
            itemIds = []
            itemNames = []
            for item in items
              itemIds.push item.itemId
              itemNames.push item.itemName
            corpAssetSearch corp, itemIds, (err, results) ->
              if err then msg.send "Error: #{err}"
              else
                found = false
                for id, quantity of results
                  if quantity > 0
                    found = true
                    msg.send "#{gTypes[id]}: #{quantity}"
                if not found
                  msg.send "None of the following found: #{itemNames.join(', ')}"
          else
            msg.send "Search was too generic, returned #{items.length} possible items"

      robot.respond /pos reactions/i, (msg) ->
        corp = getCorpData(getUsername(msg))

        if not corp?
          msg.send "You don't have a corp API key set up"
        else
          corpReactionAssets corp, (err, inventory) ->
            if err then msg.send "Error: #{err}"
            else
              for itemId, amount of inventory
                msg.send "#{gTypes[itemId]}: #{amount}"


      robot.respond /pos expect ([0-9]+) (.*)/i, (msg) ->
        num = msg.match[1]
        itemName = msg.match[2]
        corp = getCorpData(getUsername(msg))

        if not corp?
          msg.send "You don't have a corp API key set up"
        else
          maxResults = 10
          items = itemSearch gTypes, itemName
          if items.length == 0
            msg.send "No market item found for '#{itemName}'"
          else if items.length == 1
            item = items.pop()
            setInventoryAmount corp.id, item.itemId, num
            msg.send "POS inventory amount for #{item.itemName} set to #{num}"
          else if items.length <= maxResults
            itemNames = (item.itemName for item in items)
            msg.send "Ambiguous search, did you mean one of these: #{itemNames.join(', ')}"
          else
            msg.send "Search was too generic, returned #{items.length} possible items"

      robot.respond /pos expected (.*)/i, (msg) ->
        itemName = msg.match[1]
        corp = getCorpData(getUsername(msg))

        if not corp?
          msg.send "You don't have a corp API key set up"
        else
          maxResults = 10
          items = itemSearch gTypes, itemName
          if items.length == 0
            msg.send "No market item found for '#{itemName}'"
          else if items.length == 1
            item = items.pop()
            amount = getInventoryAmount corp.id, item.itemId
            msg.send "POS inventory amount for #{item.itemName} is currently #{amount ? amount : 'not set'}"
          else if items.length <= maxResults
            itemNames = (item.itemName for item in items)
            msg.send "Ambiguous search, did you mean one of these: #{itemNames.join(', ')}"
          else
            msg.send "Search was too generic, returned #{items.length} possible items"

      robot.respond /pos shopping list/i, (msg) ->
        corp = getCorpData(getUsername(msg))

        if not corp?
          msg.send "You don't have a corp API key set up"
        else
          expectedAmounts = getInventoryAmounts corp.id
          corpAssetList corp, (err, assets) ->
            shoppingList = {}
            for itemId, amount of expectedAmounts
              needed = 0
              if not assets[itemId]
                needed = amount
              else if assets[itemId] < amount
                needed = amount - assets[itemId]

              if needed > 0
                msg.send "#{gTypes[itemId]}: #{needed}"

      # set up facres notification poller
      bella = getChar "Bellatroix"

      noteworthyNotificationTypes =
        2: 'Character deleted'
        5: 'Alliance war declared'
        6: 'Alliance war surrender'
        7: 'Alliance war retracted'
        8: 'Alliance was invalidated by CONCORD'
        11: 'Bill not paid because not enough ISK available'
        16: 'New corp application'
        18: 'Corp application accepted'
        19: 'Corp tax rate changed'
        21: 'Player left corp'
        27: 'Corp declares war'
        27: 'Corp declares war'
        28: 'Corp war has started'
        29: 'Corp surrenders war'
        30: 'Corp retracts war'
        31: 'Corp war invalidated by Concord'
        37: 'Sovereignty claim fails (alliance)'
        38: 'Sovereignty claim fails (corporation)'
        39: 'Sovereignty bill late (alliance)'
        40: 'Sovereignty bill late (corporation)'
        41: 'Sovereignty claim lost (alliance)'
        42: 'Sovereignty claim lost (corporation)'
        43: 'Sovereignty claim acquired (alliance)'
        44: 'Sovereignty claim acquired (corporation)'
        45: 'Alliance anchoring alert'
        46: 'Alliance structure turns vulnerable'
        47: 'Alliance structure turns invulnerable'
        48: 'Sovereignty disruptor anchored'
        49: 'Structure won/lost'
        50: 'Corp office lease expiration notice'
        58: 'Corporation joining factional warfare'
        59: 'Corporation leaving factional warfare'
        60: 'Corporation kicked from factional warfare on startup because of too low standing to the faction'
        61: 'Character kicked from factional warfare on startup because of too low standing to the faction'
        62: 'Corporation in factional warfare warned on startup because of too low standing to the faction'
        67: 'Mass transaction reversal message'
        75: 'Tower alert'
        76: 'Tower resource alert'
        77: 'Station aggression message'
        78: 'Station state change message'
        79: 'Station conquered message'
        80: 'Station aggression message'
        81: 'Corporation requests joining factional warfare'
        82: 'Corporation requests leaving factional warfare'
        83: 'Corporation withdrawing a request to join factional warfare'
        84: 'Corporation withdrawing a request to leave factional warfare'
        85: 'Corporation liquidation'
        86: 'Territorial Claim Unit under attack'
        87: 'Sovereignty Blockade Unit under attack'
        88: 'Infrastructure Hub under attack'
        92: 'Corp Kicked'
        93: 'Customs office has been attacked'
        94: 'Customs office has entered reinforced'
        95: 'Customs office has been transferred'
        96: 'FW Alliance Warning'
        97: 'FW Alliance Kick'
        98: 'AllWarCorpJoined Msg'
        99: 'Ally Joined Defender'
        100: 'Ally Has Joined a War Aggressor'
        101: 'Ally Joined War Ally'
        102: 'New war system: entity is offering assistance in a war.'
        103: 'War Surrender Offer'
        104: 'War Surrender Declined'

      pollNotifications = ->
        notifications bella, (msgs) ->
          for msg in msgs
            if noteworthyNotificationTypes[msg.typeID]
              robot.messageRoom "#adhocracy", "EVE API Notification for Folkvangr! #{noteworthyNotificationTypes[msg.typeID]}"

      pollNotifications()

      setInterval pollNotifications, 31 * 60 * 1000

  )
