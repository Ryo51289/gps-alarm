// BS-G01 (classifyBus), BS-G02 (normalizeRouteRef).
import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

void main() {
  group('classifyBus (BS-G01)', () {
    String c(Map<String, String> tags) => classifyBus(tags).toString();

    test('cases of the spec', () {
      expect(
        classifyBus({'highway': 'bus_stop', 'name': 'Kim Mã'}).name,
        'Kim Mã',
      );
      expect(
        classifyBus({
          'public_transport': 'platform',
          'bus': 'yes',
          'name': 'Kim Mã',
        }).name,
        'Kim Mã',
      );
      expect(
        c({'public_transport': 'platform', 'name': 'Ga Hà Nội'}),
        'BusClassification(NOT_STOP)',
      );
      expect(
        c({'highway': 'bus_stop', 'bus': 'no', 'name': 'A'}),
        'BusClassification(PRIVATE)',
      );
      expect(
        c({'highway': 'bus_stop', 'disused': 'yes', 'name': 'A'}),
        'BusClassification(LIFECYCLE)',
      );
      expect(
        c({'highway': 'bus_stop', 'access': 'private', 'name': 'A'}),
        'BusClassification(PRIVATE)',
      );
      expect(c({'highway': 'bus_stop'}), 'BusClassification(NO_NAME)');
      expect(
        classifyBus({
          'highway': 'bus_stop',
          'name': 'Bach Khoa University',
          'name:vi': 'Đại học  Bách khoa ',
        }).name,
        'Đại học Bách khoa',
        reason: 'name:vi wins; spaces collapsed',
      );
    });

    test('other drops', () {
      expect(c({'name': 'A'}), 'BusClassification(NOT_STOP)');
      expect(
        c({'railway': 'tram_stop', 'name': 'A'}),
        'BusClassification(NOT_STOP)',
      );
      expect(
        c({'public_transport': 'platform', 'bus': 'no', 'name': 'A'}),
        'BusClassification(NOT_STOP)',
      );
      expect(
        c({'highway': 'bus_stop', 'proposed': 'yes', 'name': 'A'}),
        'BusClassification(LIFECYCLE)',
      );
      expect(
        c({'highway': 'bus_stop', 'construction': 'bus_stop', 'name': 'A'}),
        'BusClassification(LIFECYCLE)',
      );
      expect(
        c({'highway': 'bus_stop', 'access': 'no', 'name': 'A'}),
        'BusClassification(PRIVATE)',
      );
      expect(
        c({'highway': 'bus_stop', 'name': '   '}),
        'BusClassification(NO_NAME)',
      );
      expect(
        c({'highway': 'bus_stop', 'name': 'Москва'}),
        'BusClassification(NO_NAME)',
        reason: 'no Latin letter or digit: not searchable',
      );
    });
  });

  group('normalizeRouteRef (BS-G02)', () {
    String n(String? v) => normalizeRouteRef(v).routes.join(';');

    test('cases of the spec', () {
      expect(n('03;14'), '03;14');
      expect(n(' 03 ; 03;14 '), '03;14');
      expect(n(';;'), '');
      expect(n('1;2;3;4;5;6;7;8'), '1;2;3;4;5;6');
      expect(n('A very long ref'), '');
      expect(n('03,14'), '03,14');
    });

    test('status', () {
      expect(normalizeRouteRef(null).status, RouteRefStatus.none);
      expect(normalizeRouteRef(';;').status, RouteRefStatus.none);
      expect(normalizeRouteRef('03;14').status, RouteRefStatus.ok);
      expect(
        normalizeRouteRef('1;2;3;4;5;6;7').status,
        RouteRefStatus.truncated,
      );
      expect(
        normalizeRouteRef('03;123456789').status,
        RouteRefStatus.invalid,
        reason: 'one route of 9 characters drops the whole field',
      );
      expect(normalizeRouteRef('12345678').routes, [
        '12345678',
      ], reason: '8 characters is allowed');
      expect(normalizeRouteRef('Đ1;E 01').routes, ['Đ1', 'E 01']);
    });

    test('validRoutes and unionRoutes', () {
      expect(validRoutes(const []), isTrue);
      expect(validRoutes(const ['03', '14']), isTrue);
      expect(validRoutes(const ['03', '03']), isFalse);
      expect(validRoutes(const ['']), isFalse);
      expect(validRoutes(const ['123456789']), isFalse);
      expect(validRoutes(const ['a;b']), isFalse);
      expect(validRoutes(const ['1', '2', '3', '4', '5', '6', '7']), isFalse);
      expect(unionRoutes(const ['03', '14'], const ['14', '22']), [
        '03',
        '14',
        '22',
      ]);
      expect(unionRoutes(const ['1', '2', '3', '4', '5'], const ['6', '7']), [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
      ]);
    });
  });
}
