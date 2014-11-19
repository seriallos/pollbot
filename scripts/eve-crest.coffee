# Description:
#   Interacts with the Eve Central API
#
# Commands:
#   hubot price( ?check)? <item> - Returns average price for item.
#
# Dependencies
#   lodash

request = require 'request'
numeral = require 'numeral'
_ = require 'lodash'

prices = {}

apiBase = 'http://public-crest.eveonline.com'

loadPrices = (done) ->
  opts =
    url: "#{apiBase}/market/prices/"
    json: true

  console.log "Downloading prices"

  request opts, (err, res, body) ->
    console.log "Received prices"
    tmpPrices = {}
    for item in body.items
      name = item.type.name.toLowerCase()
      if /\sblueprint$/i.test name
        # skip it
      else
        price = item.adjustedPrice or item.averagePrice
        tmpPrices[name] =
          price: price
          niceName: item.type.name
          id: item.type.id
    prices = tmpPrices
    console.log "Prices loaded"
    if done?
      done()

findItems = (search) ->
  console.log "Searching for #{search}"
  results = []
  re = new RegExp(search,'i')
  for name, item of prices
    if name.match re
      results.push item
  return results



module.exports = (robot) ->

  loadPrices () ->
    # reload prices every 12 hours
    setInterval loadPrices, 1000 * 60 * 60 * 12

    robot.respond /price( ?check)? (.*)/i, (msg) ->
      name = msg.match[2].toLowerCase()

      if prices[name]
        item = prices[name]
      else
        items = findItems name
        if items.length == 1
          item = items[0]

      if item
        if item.price < 1000
          format = '0,0.00'
        else
          format = '0,0'
        nicePrice = numeral(item.price).format(format)
        msg.send  "#{item.niceName}: #{nicePrice} ISK"
      else
        if items
          if items.length < 10
            msg.send "No clear match, possible items: " + _.map(items, (item) -> item.niceName).join(', ')
          else
            msg.send "Search is not specific enough, please search betterer"
        else
          msg.send "Nothing found for '#{item}'"

    robot.respond /item (.*)/i, (msg) ->
      items = findItems msg.match[1]
      max = 30
      if items.length == 0
        msg.send "No items found matching that search"
      else if items.length > max
        msg.send "More than #{max} items found (#{items.length}), try a better search"
      else
        msg.send _.map(items, (item) -> item.niceName).join(', ')
