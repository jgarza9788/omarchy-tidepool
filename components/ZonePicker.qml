import QtQuick

// A time zone field ("tokyo", "new york"). The field empties after each pick
// so several zones can be added in a row.
SearchPicker {
  keepText: false
  searchCommand: "search-zones"
  resultsKey: "zones"
  placeholder: full ? "Zone limit reached (remove one first)" : "Search for a city or time zone"
  titleOf: function (r) { return r.city }
  subtitleOf: function (r) { return r.region }
  labelOf: function (r) { return r.zone }
}
