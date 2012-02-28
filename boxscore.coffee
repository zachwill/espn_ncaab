_   = require 'underscore'
fs  = require 'fs'
dom = require 'jsdom'

moment = require 'moment'
jquery = fs.readFileSync('./jquery.js').toString()

scrape_box = (error, window) ->
  $ = window.$

  # Create the in-memory data store.
  store =
    attendance: 0
    box: away: null, home: null
    conference: {}
    coverage: null
    date: {}
    final: away: null, home: null
    half: away: null, home: null
    location: null
    teams:
      away:
        abbrev: null, name: null
      home:
        abbrev: null, name: null
    totals: away: {}, home: {}
    winner: null

  # First, let's get the team names.
  team = $('.matchup > .team')
  away = team.eq(0).find('h3 > a').text()
  home = team.eq(1).find('h3 > a').text()
  store.teams.away.name = away
  store.teams.home.name = home

  # Now for time and location.
  info = $('.game-time-location > p')
  location = info.eq(1).text()
  store.location = location
  time = info.eq(0).text().split(',')
  [time, day] = [time.shift(), $.trim(time.join(','))]
  date_string = "#{day} #{time}"
  store.date =
    time: time,
    day: day,
    string: date_string,
    epoch: +moment(date_string, 'MMMM D, YYYY h:mm A zz')
  # And see if it was on TV.
  coverage = $('.game-vitals > p > strong').text() or null
  store.coverage = coverage

  # Then grab the line score.
  line = $('table.linescore')
  line.find('.periods').remove()
  team = line.find('tr')
  _(team).each (row, index) ->
    children = $(row).children()
    data = _(children).map (element) ->
      text = $(element).text()
      if not _.isNaN +text
        text = +text
      text
    if index is 0
      team_name = 'away'
    else
      team_name = 'home'
    final = data.pop()
    if not _.isNaN +final
      final = +final
    store.teams[team_name].abbrev = data.shift()
    store.final[team_name] = final
    store.box[team_name] = data
    # And, did the game go into overtime?
    if data.length > 2
      store.overtime = true
    else
      store.overtime = false

  # Create the boxscore difference array.
  [away, home] = [store.box.away, store.box.home]
  diff = []
  for num, index in away
    diff[index] = Math.abs(num - home[index])
  store.box.difference = diff
  # And, the half difference.
  [store.half.away, store.half.home] = [away[0], home[0]]
  diff = Math.abs(away[0] - home[0])
  store.half.difference = diff
  # And, the final difference.
  [away, home] = [store.final.away, store.final.home]
  store.final.difference = Math.abs(away - home)
  if away > home
    store.winner = "away"
  else
    store.winner = "home"

  # Misc data such as technicals, officials, and attendance.
  misc = $('.gp-body').children('strong')
  _(misc).each (element, index) ->
    text = $.trim(element.nextSibling.data)
    if index is 0
      if text is "None"
        text = null
      store.technicals = text
    else if index is 1
      store.officals = text.split(', ')
    else
      text = text.replace(',', '')
      if not _.isNaN +text
        text = +text
      store.attendance = text

  # Alright, finally the boxscores.
  box = $('.mod-data > tbody')
  # Let's add a starter class to those tables.
  box.eq(0).children().addClass('starter')
     .end().end()
     .eq(3).children().addClass('starter')

  # And then clean up the totals data.
  total = [box[2], box[5]]
  _(total).each (element, index) ->
    row = $(element).children('tr:first')
    row.children('td:empty').remove()
    children = row.children()
    data = _(children).map (element) ->
      stats = $(element).text().split('-')
      [+num for num in stats]
    data = _.flatten(data)
    if index is 0
      team = "away"
    else
      team = "home"
    totals = store.totals[team]
    if not data.length is 14
      # Then the total data must be malformed.
      totals.data = data
      return
    totals.fg = m: data[0], a: data[1]
    totals.three = m: data[2], a: data[3]
    totals.ft = m: data[4], a: data[5]
    totals.reb = o: data[6], total: data[7]
    [totals.ast, totals.stl] = [data[8], data[9]]
    [totals.blk, totals.to] = [data[10], data[11]]
    [totals.pf, totals.pts] = [data[12], data[13]]

  # Append players to one table per team.
  [away, home] = [box.eq(0), box.eq(3)]
  box.eq(1).children().appendTo(away)
  box.eq(4).children().appendTo(home)

  console.log store

dom.env
  html: "./box.html"
  src: [jquery]
  done: scrape_box
