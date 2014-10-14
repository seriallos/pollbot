# Description:
#   Interacts with the Eve Central API
#
# Commands:
#   hubot price( ?check)? <item> - Returns average price for item.

request = require 'request'
numeral = require 'numeral'

prices = {}

apiBase = 'http://public-crest.eveonline.com'

loadPrices = (done) ->
  opts =
    url: "#{apiBase}/market/prices/"
    json: true

  console.log "Downloading prices"

  request opts, (err, res, body) ->
    console.log "Received prices"
    prices = {}
    for item in body.items
      name = item.type.name.toLowerCase()
      if /\sblueprint$/i.test name
        console.log "Skipping #{name}"
      else
        price = item.adjustedPrice or item.averagePrice
        prices[name] =
          price: price
          niceName: item.type.name
    done()

findItems = (search) ->
  console.log "Searching for #{search}"
  results = []
  re = new RegExp(search,'i')
  for name, item of prices
    if name.match re
      results.push item.niceName
  return results


loadPrices () ->
  console.log "Prices laoded"

module.exports = (robot) ->

  robot.respond /price( ?check)? (.*)/i, (msg) ->
    item = msg.match[2].toLowerCase()
    if prices[item]
      item = prices[item]
      if item.price < 1000
        format = '0,0.00'
      else
        format = '0,0'
      nicePrice = numeral(item.price).format(format)
      msg.send  "#{item.niceName}: #{nicePrice} ISK"
    else
      msg.send "No prices found for '#{item}'"

  robot.respond /item (.*)/i, (msg) ->
    items = findItems msg.match[1]
    max = 30
    if items.length == 0
      msg.send "No items found matching that search"
    else if items.length > max
      msg.send "More than #{max} items found (#{items.length}), try a better search"
    else
      msg.send items.join(', ')
