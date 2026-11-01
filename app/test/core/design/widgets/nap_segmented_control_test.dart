// TC21-TC23: NapSegmentedControl.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

const List<NapSegment<int>> _segments = [
  NapSegment(value: 0, label: 'Khoảng cách'),
  NapSegment(value: 1, label: 'Thời gian'),
  NapSegment(value: 2, label: 'Thông minh'),
];

void main() {
  testWidgets('TC21 tap changes, re-tap and disabled do not', (tester) async {
    final calls = <int>[];
    await pumpNap(
      tester,
      NapSegmentedControl<int>(
        segments: _segments,
        selected: 0,
        semanticLabel: 'Báo khi',
        onChanged: calls.add,
      ),
    );
    await tester.tap(find.text('Thông minh'));
    expect(calls, [2]);
    await tester.tap(find.text('Khoảng cách'));
    expect(calls, [2]);

    for (final s in _segments) {
      expect(
        tester.getSemantics(find.text(s.label)),
        isSemantics(
          label: s.label,
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          isSelected: s.value == 0,
        ),
      );
    }
    // Touch area covers the track padding: 44 + 2 x 4.
    expect(
      tester
          .getSize(
            find
                .descendant(
                  of: find.byType(NapSegmentedControl<int>),
                  matching: find.byType(GestureDetector),
                )
                .first,
          )
          .height,
      greaterThanOrEqualTo(52),
    );

    await pumpNap(
      tester,
      NapSegmentedControl<int>(
        segments: _segments,
        selected: 0,
        onChanged: null,
      ),
    );
    await tester.tap(find.text('Thời gian'));
    expect(calls, [2]);
    expect(
      tester.getSemantics(find.text('Thời gian')),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
  });

  test('TC22 invalid configurations assert', () {
    expect(
      () => NapSegmentedControl<int>(
        segments: const [NapSegment(value: 0, label: 'a')],
        selected: 0,
        onChanged: null,
      ),
      throwsAssertionError,
    );
    expect(
      () => NapSegmentedControl<int>(
        segments: [
          for (var i = 0; i < 5; i++) NapSegment(value: i, label: '$i'),
        ],
        selected: 0,
        onChanged: null,
      ),
      throwsAssertionError,
    );
    expect(
      () => NapSegmentedControl<int>(
        segments: const [
          NapSegment(value: 0, label: 'a'),
          NapSegment(value: 0, label: 'b'),
        ],
        selected: 0,
        onChanged: null,
      ),
      throwsAssertionError,
    );
    expect(
      () => NapSegmentedControl<int>(
        segments: _segments,
        selected: 7,
        onChanged: null,
      ),
      throwsAssertionError,
    );
  });

  testWidgets('TC23 reduced motion: zero animation duration', (tester) async {
    await pumpNap(
      tester,
      NapSegmentedControl<int>(
        segments: _segments,
        selected: 1,
        onChanged: (_) {},
      ),
      disableAnimations: true,
    );
    for (final box in tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    )) {
      expect(box.duration, Duration.zero);
    }

    await pumpNap(
      tester,
      NapSegmentedControl<int>(
        segments: _segments,
        selected: 1,
        onChanged: (_) {},
      ),
    );
    expect(
      tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
          .duration,
      NapMotion.fast,
    );
  });
}
