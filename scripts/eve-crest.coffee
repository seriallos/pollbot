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
      prices[name] = price
    done()

loadPrices () ->
  console.log "Prices laoded"

module.exports = (robot) ->

  robot.respond /price( ?check)? (.*)/i, (msg) ->
    item = msg.match[2].toLowerCase()
    if prices[item]
      msg.send numeral(prices[item]).format('0,0.00')
    else
      msg.send "No prices found for '#{item}'"

