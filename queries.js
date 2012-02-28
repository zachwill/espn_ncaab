/**
 * A couple of useful queries for interacting with MongoDB.
 */

db.ncb.group({
  initial: {
    count: 0,
    total: 0
  },
  reduce: function(doc, out) {
    var length = doc.plays.length
    if (length > 0) {
      out.count += 1
      out.total += length
    }
  },
  finalize: function(out) {
    out.average = out.total / out.count
  }
})


db.ncb.group({
  initial: {
    games: []
  },
  reduce: function(doc, out) {
    var length = doc.plays.length
    if (length > 0) {
      out.games.push(length)
    }
  },
  finalize: function(out) {
    average = function(a){
      var t = a.length,
          r = {mean: 0, variance: 0, deviation: 0};
      for(var m, s = 0, j = t; j--; s += a[j]);
      for(m = r.mean = s / t, j = t, s = 0; j--; s += Math.pow(a[j] - m, 2));
      return r.deviation = Math.sqrt(r.variance = s / t), r;
    }
    return average(out.games)
  }
})
