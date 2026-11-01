// TC02 (train), TC03 (road).
import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

Classification c(Map<String, String> tags) => classify(tags);

void main() {
  group('train (TC02)', () {
    test('railway=station without station=* is a train station', () {
      expect(c({'railway': 'station', 'name': 'Vinh'}).kind, StationKind.train);
    });

    test('railway=halt', () {
      expect(c({'railway': 'halt', 'name': 'X'}).kind, StationKind.train);
    });

    test('public_transport=station + train=yes', () {
      expect(
        c({'public_transport': 'station', 'train': 'yes', 'name': 'X'}).kind,
        StationKind.train,
      );
    });

    test('metro filters', () {
      expect(
        c({'railway': 'station', 'station': 'subway', 'name': 'X'}).drop,
        DropReason.metro,
      );
      expect(
        c({'railway': 'station', 'subway': 'yes', 'name': 'X'}).drop,
        DropReason.metro,
      );
      expect(
        c({'railway': 'station', 'subway': 'yes', 'train': 'yes', 'name': 'X'})
            .kind,
        StationKind.train,
      );
      expect(
        c({'railway': 'station', 'network': 'Hanoi Metro', 'name': 'X'}).drop,
        DropReason.metro,
      );
      expect(
        c({
          'railway': 'station',
          'operator': 'Ban Quản lý Đường sắt đô thị',
          'name': 'X',
        }).drop,
        DropReason.metro,
      );
      expect(
        c({'railway': 'station', 'station': 'funicular', 'name': 'X'}).drop,
        DropReason.metro,
      );
    });

    test('lifecycle', () {
      expect(
        c({'railway': 'station', 'disused': 'yes', 'name': 'X'}).drop,
        DropReason.lifecycle,
      );
      expect(
        c({'railway': 'station', 'construction': 'yes', 'name': 'X'}).drop,
        DropReason.lifecycle,
      );
      expect(
        c({
          'public_transport': 'station',
          'train': 'yes',
          'railway': 'disused',
          'name': 'X',
        }).drop,
        DropReason.lifecycle,
      );
    });

    test('private', () {
      expect(
        c({'railway': 'station', 'access': 'private', 'name': 'X'}).drop,
        DropReason.private,
      );
    });

    test('no name, or a name without Latin letters', () {
      expect(c({'railway': 'station'}).drop, DropReason.noName);
      expect(c({'railway': 'station', 'name': '  '}).drop, DropReason.noName);
      expect(
        c({'amenity': 'bus_station', 'name': 'Камрань'}).drop,
        DropReason.noName,
      );
    });

    test('name:vi preferred over name', () {
      expect(rawNameOf({'name': 'Hanoi', 'name:vi': ' Hà Nội '}), 'Hà Nội');
    });
  });

  group('road (TC03)', () {
    Classification road(String name, [Map<String, String> more = const {}]) =>
        c({'amenity': 'bus_station', 'name': name, ...more});

    test('coach by name', () {
      expect(road('Bến xe Mỹ Đình').kind, StationKind.coach);
      expect(road('Bến xe Mỹ Đình').guessed, isFalse);
      expect(road('Trạm xe khách X').kind, StationKind.coach);
    });

    test('bus by name', () {
      expect(road('Bến xe buýt Yên Nghĩa').kind, StationKind.bus);
      expect(road('Điểm trung chuyển Long Biên').kind, StationKind.bus);
      expect(road('Điểm đầu cuối Kim Mã').kind, StationKind.bus);
      expect(road('BRT Kim Mã').kind, StationKind.bus);
    });

    test('no evidence: bus, guessed', () {
      final r = road('Bến Thành');
      expect(r.kind, StationKind.bus);
      expect(r.guessed, isTrue);
    });

    test('coach=yes', () {
      expect(road('Trạm Xuân Mai', {'coach': 'yes'}).kind, StationKind.coach);
    });

    test('public_transport=station + bus=yes', () {
      expect(
        c({'public_transport': 'station', 'bus': 'yes', 'name': 'Bến xe A'})
            .kind,
        StationKind.coach,
      );
    });

    test('roadside stops are not stations', () {
      expect(
        road('Nhà chờ X', {'highway': 'bus_stop'}).drop,
        DropReason.notStation,
      );
      expect(
        road('X', {'public_transport': 'platform'}).drop,
        DropReason.notStation,
      );
    });

    test('train wins when both', () {
      expect(
        c({'railway': 'station', 'amenity': 'bus_station', 'name': 'Bến xe A'})
            .kind,
        StationKind.train,
      );
    });

    test('neither train nor road', () {
      expect(c({'name': 'X'}).drop, DropReason.notStation);
    });
  });
}
