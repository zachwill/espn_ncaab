_   = require 'underscore'
fs  = require 'fs'
dom = require 'jsdom'

# MongoDB ftw.
# db = require('mongous').Mongous

# And let's read in jQuery.
jquery = fs.readFileSync('./jquery.js').toString()

# Custom request headers -- mostly used for user agent spoofing.
HEADERS =
  'User-Agent': 'Mozilla/5.0 (X11; U; Linux x86; en-US; rv:1.9.2.7) Gecko/20100809 LOL Firefox/3.6.7'


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


# A class that can be used to scrape play-by-plays and boxscores from ESPN for
# all NCAA Men's Basketball games.
class NCB
  constructor: (@id) ->
    @headers = HEADERS
    @_period = 1

  endpoints: ->
    box: "boxscore?gameId=#{@id}"
    espn: "http://scores.espn.go.com/ncb/"
    play: "playbyplay?gameId=#{@id}"

  # Scrape the game's play-by-play data. A callback can be passed to this
  # function that will then be executed after the scraping.
  plays: (@after) ->
    # Just make sure that the period is 1.
    @_period = 1
    url = @endpoints()
    [espn, play] = [url.espn, url.play]
    dom.env
      html: "#{espn}#{play}"
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
    if @after? then @after(data)

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


do ->
  ncb = new NCB("320032539")
  ncb.plays (data) ->
    fs.writeFileSync "320032539.plays.json", JSON.stringify(data)
  #day = new Day('2012-02-22')
  #day.games (games) -> console.log games
