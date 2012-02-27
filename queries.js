/**
 * A couple of useful queries for interacting with MongoDB.
 */

db.test.group({
  initial: {
    count: 0,
    average: 0
  },
  reduce: function(doc, out) {
    var length = doc.plays.length
    if (length > 0) {
      out.count += 1
      out.average += length
    }
  },
  finalize: function(out) {
    out.average = out.average / out.count
  }
})
