_   = require 'underscore'
fs  = require 'fs'
dom = require 'jsdom'

moment = require 'moment'
jquery = fs.readFileSync('./jquery.js').toString()

# MongoDB ftw.
# db = require('mongous').Mongous

# Custom request headers -- mostly used for user agent spoofing.
HEADERS =
  'User-Agent': 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6;en-US; rv:1.9.2.9) Gecko/20100824 Firefox/3.6.9'


# Generate an array of 'YYYY-MM-DD' dates that exist between and include
# two other dates in 'YYYY-MM-DD' or 'MM-DD-YYYY' format.
between = (start, end) ->
  days = []
  start = moment(start, ['YYYY-MM-DD', 'MM-DD-YYYY'])
  end = moment(end, ['YYYY-MM-DD', 'MM-DD-YYYY'])
  if start > end
    [start, end] = [end, start]
  while start <= end
    format = start.format('YYYY-MM-DD')
    days.push(format)
    start.add('days', 1)
  days


# Scrape game IDs for a specific date (in YYYY-MM-DD format).
class Day
  constructor: (@date, @league='ncb') ->
    @headers = HEADERS

  endpoint: ->
    date = @date.replace(/-/g, '')
    espn = "http://scores.espn.go.com/#{@league}/"
    "#{espn}scoreboard?date=#{date}&confId=50"

  games: (@after, date) ->
    if date?
      @date = date
    endpoint = @endpoint()
    dom.env
      html: endpoint
      headers: @headers
      src: [jquery]
      done: @scrape_games

  scrape_games: (error, window) =>
    $ = window.$
    links = $('.expand-gameLinks')
    games = _(links).map (game) ->
      id = game.id.match(/[0-9]+/)
      return id[0] unless _.isEmpty id
    if @after? then @after(games)


# A class that can scrape ESPN boxscores.
class Boxscore
  constructor: (@id) ->
    @headers = HEADERS

  endpoints: ->
    box: @id

  boxscore: (@_callback) ->
    url = @endpoints()
    dom.env
      html: url.box
      headers: @headers
      src: [jquery]
      done: @scrape_box

  # Create the in-memory data store.
  data_store: ->
    attendance: 0
    box: away: null, home: null
    conference: {}
    coverage: null
    date: {}
    final: away: null, home: null
    half: away: null, home: null
    location: null
    players: away: [], home: []
    teams:
      away:
        abbrev: null, name: null
      home:
        abbrev: null, name: null
    totals: away: {}, home: {}
    winner: null

  scrape_box: (error, window) =>
    $ = window.$
    store = @data_store()
    console.log window.location.search

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
    teams = {}
    [teams.away, teams.home] = [box.eq(0), box.eq(3)]
    box.eq(1).children().appendTo(teams.away)
    box.eq(4).children().appendTo(teams.home)

    # Alright, let's get individual player stats.
    for location, team of teams
      rows = team.children()
      data = _(rows).map (row, index) ->
        out = {}
        row = $(row)
        stats = row.children()
        player = stats.eq(0).remove()
        [name, pos] = player.text().split(', ')
        if pos?
          pos = pos.split('-')
        [out.name, out.position] = [name, pos]
        out.starter = row.hasClass('starter')

        # Now the rest of stats are numbers.
        numbers = _(stats).map (stat) ->
          list = $(stat).text().split('-')
          [+num for num in list]
        numbers = _.flatten(numbers)
        out.min = numbers[0]
        out.fg = m: numbers[1], a: numbers[2]
        out.three = m: numbers[3], a: numbers[4]
        out.ft = m: numbers[5], a: numbers[6]
        out.reb = o: numbers[7], total: numbers[8]
        [out.ast, out.stl] = [numbers[9], numbers[10]]
        [out.blk, out.to] = [numbers[11], numbers[12]]
        [out.pf, out.pts] = [numbers[13], numbers[14]]
        store.players[location].push(out)
    # And let's pass all the data to the callback function.
    if @_callback? then @_callback(store)


# A class that can be used to scrape play-by-plays and boxscores from ESPN for
# all NCAA Men's Basketball games.
class NCB extends Boxscore
  constructor: (@id) ->
    @headers = HEADERS
    @_period = 1
    # Make sure to bind the scrape_box function.
    @scrape_box = _.bind(@scrape_box, @)

  # Check to see whether a local file was given as the game ID.
  endpoints: ->
    id = @id
    espn = "http://scores.espn.go.com/ncb"
    if not id.match('./')
      url =
        box:  "#{espn}/boxscore?gameId=#{id}"
        play: "#{espn}/playbyplay?gameId=#{id}"
    else
      url =
        box:  id
        play: id
    url

  # Scrape the game's play-by-play data. A callback can be passed to this
  # function that will then be executed after the scraping.
  plays: (@_after) ->
    # Just make sure that the period is 1.
    @_period = 1
    url = @endpoints()
    dom.env
      html: url.play
      headers: @headers
      src: [jquery]
      done: @scrape_plays

  # Actual method that scrapes the play-by-by table rows.
  scrape_plays: (error, window) =>
    $ = window.$
    rows = $('.mod-data > tr')
    console.log rows.length
    data = _(rows).map (row) =>
      row = $(row)
      children = row.children()
      length = children.length
      bold = children.find('b')
      if not _.isEmpty bold.html()
        # Then remove the bold element.
        text = bold.text()
        bold.parent().append(text).end().remove()
        if length is 4
          scored = true
      if length is 4
        play = _(children).map @outcome
      else
        play = _(children).map (element) -> element.innerHTML
      @create_play play, scored
    if @_after? then @_after(data)

  # Get the individual outcome for individual plays. Also, calculate the
  # difference between the home and away teams' current scores.
  outcome: (element, index) ->
    html = element.innerHTML
    if index is 0
      return html
    else if not _.isEmpty html.match('&nbsp;')
      html = null
    else if not _.isEmpty html.match(/[0-9]/)
      [away, home] = html.split('-')
      diff = Math.abs(away - home)
      html =
        away: +away
        difference: diff
        home: +home
    html

  create_play: (play, scored=false) ->
    official = null
    if play.length is 2
      official = true
      [time, text] = play
      [away, home, score] = [null, null, null]
      if text.match('End of the')
        update = true
    else
      [time, away, score, home] = play
      if _.isString away
        text = away
      else
        text = home
    time = @update_time(time)
    data =
      action:
        scored: scored
        text: text
      period: @_period
      play:
        away: away
        home: home
        official: official
      score: score
      time: time
    if update then @_period += 1
    data

  update_time: (time) ->
    period = @_period
    if period > 2
      overall = (period - 2) * 5 + 40
    else
      overall = period * 20
    [minutes, seconds] = _(time.split(':')).map (value) -> +value
    minutes = overall - minutes
    if seconds isnt 0
      seconds = 60 - seconds
      minutes -= 1
    if seconds < 10
      seconds = '0' + seconds
    elapsed = "#{minutes}:#{seconds}"
    return elapsed: elapsed, game: time


exports.between = between
exports.Boxscore = Boxscore
exports.Day = Day
exports.NCB = NCB
