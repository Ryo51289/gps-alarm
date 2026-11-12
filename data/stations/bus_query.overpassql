[out:json][timeout:300];
rel["ISO3166-2"~"^VN-(HN|SG)$"][boundary=administrative];
map_to_area->.cities;
(
  node(area.cities)[highway=bus_stop];
  node(area.cities)[public_transport=platform][bus=yes];
  way(area.cities)[public_transport=platform][bus=yes];
)->.bs;
.bs out center;
foreach.cities->.c(
  .c out tags;
  nwr.bs(area.c);
  out ids;
);
