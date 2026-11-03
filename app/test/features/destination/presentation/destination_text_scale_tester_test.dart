// Tester T23 (adversarial, beyond TW26): screen 2 at text scale 2.0 in vi and
// en, on the wireframe size and on a small phone (360×640), in every list
// state: empty, long station names selected, Places results, Places not
// configured / no key (map placeholder), Places error banner, catalog error.
// Pass = no layout exception (overflow) and the confirm button stays on
// screen and tappable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';

import 'destination_harness.dart';

const _small = Size(360, 640);

typedef _Strings = ({
  String placesEntryEmpty,
  String chooseDisabled,
  String choose,
  String notConfigured,
  String unavailable,
  String mapUnavailable,
  String catalogError,
  String Function(String q) placesEntry,
});

const _Strings _vi = (
  placesEntryEmpty: 'Tìm địa chỉ bằng Google Maps',
  chooseDisabled: 'Chọn điểm đến',
  choose: 'Chọn ',
  notConfigured: 'Bản này chưa bật tìm địa chỉ.',
  unavailable: 'Tìm địa chỉ tạm thời không dùng được.',
  mapUnavailable: 'Bản đồ chưa sẵn sàng trong bản này.',
  catalogError:
      'Không tải được danh sách ga, bến xe. Bạn vẫn tìm được địa chỉ qua '
      'Google Maps.',
  placesEntry: _viEntry,
);

const _Strings _en = (
  placesEntryEmpty: 'Search addresses with Google Maps',
  chooseDisabled: 'Choose a destination',
  choose: 'Choose ',
  notConfigured: 'Address search is not set up in this build.',
  unavailable: 'Address search is unavailable right now.',
  mapUnavailable: 'The map is not available in this build.',
  catalogError:
      "Couldn't load stations. You can still search addresses with Google "
      'Maps.',
  placesEntry: _enEntry,
);

String _viEntry(String q) => 'Tìm "$q" bằng Google Maps';
String _enEntry(String q) => 'Search "$q" with Google Maps';

/// The confirm button: on screen, inside the view, no exception so far.
void _expectSane(WidgetTester tester, String reason) {
  expect(tester.takeException(), isNull, reason: reason);
  final button = find.byType(NapButton);
  expect(button, findsWidgets, reason: reason);
  final rect = tester.getRect(button.last);
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.bottom, lessThanOrEqualTo(view.height + 0.5), reason: reason);
  expect(rect.top, greaterThanOrEqualTo(0), reason: reason);
  expect(rect.height, greaterThanOrEqualTo(44), reason: reason);
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void main() {
  for (final (locale, s) in [
    (const Locale('vi'), _vi),
    (const Locale('en'), _en),
  ]) {
    for (final size in [null, _small]) {
      final tag = '${locale.languageCode} ${size ?? '390x844'}';

      testWidgets('X1 [$tag] 2.0: empty, long names, selected', (tester) async {
        await pumpDestination(tester, textScale: 2, locale: locale);
        if (size != null) {
          await _resize(tester, size);
        }
        _expectSane(tester, 'empty');
        expect(find.text(s.placesEntryEmpty), findsOneWidget);
        expect(find.text(s.chooseDisabled), findsOneWidget);

        // Longest names of the dataset (bus 49 chars, coach 47 chars).
        await typeQuery(tester, 'cho thue xe du lich cocovip');
        _expectSane(tester, 'longest bus');
        await typeQuery(tester, 'ben xe khach phia bac buon ma thuot');
        _expectSane(tester, 'long coach');
        const name = 'Bến xe khách phía bắc Thành phố Buôn Ma Thuột';
        await tapVisible(tester, find.text(name).first);
        _expectSane(tester, 'selected long');
        expect(find.textContaining(s.choose + name), findsOneWidget);
        await tester.tap(find.textContaining(s.choose + name));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('X2 [$tag] 2.0: Places results, error banner', (
        tester,
      ) async {
        final h = await pumpDestination(tester, textScale: 2, locale: locale);
        if (size != null) {
          await _resize(tester, size);
        }
        await typeQuery(tester, 'duc long');
        await tapVisible(tester, find.text(s.placesEntry('duc long')));
        _expectSane(tester, 'places results');
        expect(find.text('Google Maps'), findsOneWidget);
        await tapVisible(tester, find.text('Bến xe Đức Long'));
        _expectSane(tester, 'places selected');
        h.places.autocompleteStatus = 503;
        await typeQuery(tester, 'duc long gia lai');
        expect(find.text(s.unavailable), findsOneWidget);
        _expectSane(tester, 'places banner');
      });

      testWidgets('X3 [$tag] 2.0: no key (map placeholder, not configured)', (
        tester,
      ) async {
        await pumpDestination(
          tester,
          textScale: 2,
          locale: locale,
          mapsKey: null,
        );
        if (size != null) {
          await _resize(tester, size);
        }
        _expectSane(tester, 'placeholder');
        await tapVisible(tester, find.text(s.placesEntryEmpty));
        expect(find.text(s.notConfigured), findsOneWidget);
        _expectSane(tester, 'not configured');
        // Collapse the panel by choosing a station: placeholder fully shown.
        await tapVisible(tester, find.byType(NapChip).first);
        await typeQuery(tester, 'dong hoi');
        await tapVisible(tester, find.text('Ga Đồng Hới').first);
        _expectSane(tester, 'placeholder collapsed');
        expect(find.text(s.mapUnavailable), findsOneWidget);
      });

      testWidgets('X4 [$tag] 2.0: catalog error banner', (tester) async {
        await pumpDestination(
          tester,
          textScale: 2,
          locale: locale,
          stationCatalog: () async =>
              throw const StationDataException('broken'),
        );
        if (size != null) {
          await _resize(tester, size);
        }
        expect(find.text(s.catalogError), findsOneWidget);
        _expectSane(tester, 'catalog error');
      });
    }
  }
}
