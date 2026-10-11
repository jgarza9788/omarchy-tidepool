import QtQuick

// A city field (Open-Meteo search). Picking one stores the place's coordinates
// as well as its name, so the weather never lands on the wrong "Springfield".
SearchPicker {
  keepText: true
  searchCommand: "search-city"
  resultsKey: "places"
  placeholder: "Search for a city"
  titleOf: function (r) { return r.name }
  subtitleOf: function (r) { return [r.region, r.country].filter(function (x) { return x }).join(", ") }
  labelOf: function (r) { return r.label }
}
