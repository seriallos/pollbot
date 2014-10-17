module.exports = (robot) ->
  robot.router.post '/hubot/whappalert', (req, res) ->

    console.log "Received POST at /hubot/whappalert"

    data = req.body

    message = "#{data.severity} Alert: #{data.summary} (from #{data.raised_by})"

    robot.messageRoom "#adhocracy", message

    res.send 'OK'
