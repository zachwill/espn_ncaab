_ = require 'underscore'
fs = require 'fs'
repl = require 'repl'
zombie = require 'zombie'

# Database stuff.
db = require('mongous').Mongous

# Read in the static `Zepto.js` file synchronously. It will eventually be
# evaluated by a `Zombie.js` browser instance.
zepto = fs.readFileSync 'zepto.js', 'utf-8', (error, data) -> data

# Browser options that will be used by Zombie.js when visiting the indiviudal
# pages. No scripts or CSS should be loaded, and a Firefox 3.6.7 user-agent
# string should be used.
OPTIONS =
  debug: true
  loadCSS: false
  runScripts: false
  site: 'http://scores.espn.go.com/ncb/'
  userAgent: "Mozilla/5.0 (X11; U; Linux x86; en-US; rv:1.9.2.7) Gecko/20100809 LOL Firefox/3.6.7"


# Load Zepto into a browser instance. Zepto's way smaller than jQuery (there's
# no need for the IE hacks now), but has much of the same syntax.
class Zepto
  constructor: (browser) ->
    browser.evaluate "eval(#{zepto})"
    return browser.window.$


# Scrape all game ID's for a given day. These games can then be individually
# scraped and saved to the database.
class Day
  constructor: (date, @callback) ->
    scores = "scoreboard?date=#{date}&confId=50"
    zombie.visit scores, OPTIONS, @scrape

  scrape: (error, browser) =>
    $ = Zepto(browser)
    expand = $('.expand-gameLinks')
    games = expand.map @match
    if @callback
      return @callback(games)
    games

  # Use a regular expression to match a game's ID against an element's actual
  # `id` attribute.
  match: (index, game) ->
    id = game.id.match(/[0-9]+/)
    return id[0] unless _.isEmpty id


# Scrape the necessary information from an individual game. Note that
# `zombie.visit` is used -- which creates a one-off browser instance. This
# allows scraping multiple games and pages to be completely asynchronous.
class Game
  constructor: (id) ->
    return if _.isEmpty id
    @url =
      boxscore: "boxscore?gameId=#{id}"
      plays: "playbyplay?gameId=#{id}"
    @data = {}
    @period = 1
    @scrape id

  # The scrape method is a little convoluted since the `Zombie.js` requests are
  # being sent asynchronously.
  scrape: (id) ->
    zombie.visit @url.plays, OPTIONS, (error, browser) =>
      @data.plays = @plays browser
      browser.visit @url.boxscore, (error, browser) =>
        @boxscore browser

  boxscore: (browser) ->
    $ = Zepto(browser)
    tables = $('.mod-data > tbody')
    console.log "#{tables.length} tables"

  plays: (browser) ->
    $ = Zepto(browser)
    rows = $('table.mod-pbp > tr')
    console.log rows.length
    rows.map (index, row) =>
      row = $(row)
      children = row.children()
      length = children.length
      bold = children.find('b')
      if not _.isEmpty bold
        text = bold.text()
        bold.parent().append(text).end().remove()
        if length is 4
          scored = true
      if length is 4
        play = children.map @outcome
      else
        play = children.map (index, element) -> element.innerHTML
      @create_play play, scored

  outcome: (index, element) ->
    html = element.innerHTML
    if index is 0
      return html
    else if not _.isEmpty html.match('&nbsp;')
      html = null
    else if not _.isEmpty html.match(/[0-9]/)
      [away, home] = html.split('-')
      diff = Math.abs(away - home)
      html =
        away: away
        diffence: diff
        home: home
    html

  create_play: (play, scored=false) ->
    official = null
    if play.length is 2
      official = true
      [time, text] = play
      [away, home, score] = [null, null, null]
      if text.match('End of the')
        update = true
    else if _.isString play[1]
      [time, away, score] = play
      [text, home] = [away, null]
    else
      [time, score, home] = play
      [text, away] = [home, null]
    time = @update_time(time)
    data =
      action:
        scored: scored
        text: text
      period: @period
      play:
        away: away
        home: home
        official: official
      score: score
      time: time
    if update then @period += 1
    data

  update_time: (time) ->
    if @period > 2
      overall = (@period - 2) * 5 + 40
    else
      overall = @period * 20
    [minutes, seconds] = _(time.split(':')).map (value) -> +value
    minutes = overall - minutes
    if seconds isnt 0
      seconds = 60 - seconds
      minutes -= 1
    if seconds < 10
      seconds = '0' + seconds
    elapsed = "#{minutes}:#{seconds}"
    return {
      elapsed: elapsed
      game: time
    }


# Extend scraped game output against a default object.
# TODO: Refactor this to a `Save` class without the large `original` object.
class Output
  constructor: (refined={}) ->
    original =
      attendance: null
      conference:
        game: null
        name: null
      date:
        string: null
      espn: null
      final:
        away: null
        home: null
      half:
        away: null
        home: null
      location: null
      overtime: false
      plays: []
      players:
        away: []
        home: []
      totals:
        away: null
        home: null
      winner: null
    return _.extend original, refined


id = '320072031'
day = '20120103'
last = (games) ->
  return if _.isEmpty games
  console.log games.length
  last = _.last games
  new Game(last)

do ->
  new Day day, last
  new Game id
