// Tester T23 (adversarial, beyond TW26): screen 2 at text scale 2.0 in vi and
// en, on the wireframe size, a small phone (360×640) and, since T23.2 (RW07),
// 320×568, in every list state: empty, long station names selected, no map
// (placeholder), catalog error.
// Pass = no layout exception (overflow) and the confirm button stays on
// screen and tappable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';

import 'destination_harness.dart';

const _small = Size(360, 640);

/// T23.2 RW07: the smallest phone the spec checks.
const _tiny = Size(320, 568);

typedef _Strings = ({
  String startTyping,
  String chooseDisabled,
  String choose,
  String mapUnavailable,
  String catalogError,
});

const _Strings _vi = (
  startTyping: 'Gõ tên ga hoặc bến xe.',
  chooseDisabled: 'Chọn điểm đến',
  choose: 'Chọn ',
  mapUnavailable: 'Bản đồ chưa có trong bản này.',
  catalogError: 'Không tải được danh sách ga, bến xe.',
);

const _Strings _en = (
  startTyping: 'Type a station name.',
  chooseDisabled: 'Choose a destination',
  choose: 'Choose ',
  mapUnavailable: "The map isn't available in this build.",
  catalogError: "Couldn't load stations.",
);

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
    for (final size in [null, _small, _tiny]) {
      final tag = '${locale.languageCode} ${size ?? '390x844'}';

      testWidgets('X1 [$tag] 2.0: empty, long names, selected', (tester) async {
        await pumpDestination(tester, textScale: 2, locale: locale);
        if (size != null) {
          await _resize(tester, size);
        }
        _expectSane(tester, 'empty');
        expect(find.text(s.startTyping), findsOneWidget);
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

      testWidgets('X3 [$tag] 2.0: no map builder (placeholder)', (
        tester,
      ) async {
        await pumpDestination(
          tester,
          textScale: 2,
          locale: locale,
          withMap: false,
        );
        if (size != null) {
          await _resize(tester, size);
        }
        _expectSane(tester, 'placeholder');
        // Collapse the panel by choosing a station: placeholder fully shown.
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
