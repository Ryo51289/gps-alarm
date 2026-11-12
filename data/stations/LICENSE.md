# License of the NapStop station data

The station database `app/assets/stations.json` and the files in `data/stations/` that come from OpenStreetMap
(`raw/overpass.json`, and the data selected, cleaned and corrected from it by `tools/stationgen` with
`overrides.json`) are a Derivative Database of OpenStreetMap. The same also applies to the bus stop database
`app/assets/bus_stops.json` and `data/stations/raw/bus_*` (with `bus_overrides.json`).

**© OpenStreetMap contributors.** Source and copyright: <https://www.openstreetmap.org/copyright>

This database is made available under the **Open Database License (ODbL) 1.0**:
<https://opendatacommons.org/licenses/odbl/1-0/>.

You are free to share, create and adapt this database as long as you attribute OpenStreetMap and its contributors,
keep any derived database under the ODbL, and keep it open (ODbL §4.2, §4.4, §4.6).

Other files:

- `provinces.json` lists the provincial units of Viet Nam and their merger under Resolution 202/2025/QH15 of the
  National Assembly. Legal documents are not protected by copyright in Viet Nam (Law on Intellectual Property,
  Article 15); the table is factual administrative information.
- `must_have.json`, `bus_must_have.json`, `fold_vectors.json`, `query.overpassql`, `bus_query.overpassql`,
  `BUILD_REPORT.md` and `BUS_BUILD_REPORT.md` are project files; they are
  distributed with the database under the same terms.
