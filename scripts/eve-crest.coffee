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

  request opts, (err, res, body) ->
    prices = {}
    for item in body.items
      name = item.type.name.toLowerCase()
      price = item.adjustedPrice
      prices[name] =
        price: price
        niceName: item.type.name
    done()

loadPrices () ->
  console.log "Prices laoded"

module.exports = (robot) ->

  robot.respond /price( ?check)? (.*)/i, (msg) ->
    item = msg.match[2].toLowerCase()
    if prices[item]
      item = prices[item]
      nicePrice = numeral(item.price).format('0,0')
      msg.send  "#{item.niceName}: #{nicePrice} ISK"
    else
      msg.send "No prices found for '#{item}'"

