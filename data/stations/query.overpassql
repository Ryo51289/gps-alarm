[out:json][timeout:300];
area["ISO3166-1"="VN"][admin_level=2][boundary=administrative]->.vn;
(
  nwr(area.vn)[railway~"^(station|halt)$"];
  nwr(area.vn)[public_transport=station][train=yes];
  nwr(area.vn)[amenity=bus_station];
  nwr(area.vn)[public_transport=station][bus=yes];
)->.st;
.st out center;
rel(area.vn)[boundary=administrative][admin_level=4];
map_to_area->.provs;
foreach.provs->.p(
  .p out tags;
  nwr.st(area.p);
  out ids;
);
