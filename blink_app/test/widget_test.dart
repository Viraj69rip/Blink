import 'package:blink_app/main.dart';
import 'package:blink_app/providers/robot_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('liquid navigation switches between app sections',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RobotStateProvider(),
        child: const MaterialApp(home: BlinkHome()),
      ),
    );

    expect(find.text('Command'), findsOneWidget);

    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();

    expect(find.text('Draw'), findsWidgets);
    expect(find.text('PIXEL GRID · 128 × 64 OLED'), findsOneWidget);
  });

  testWidgets('content drags do not switch tabs', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RobotStateProvider(),
        child: const MaterialApp(home: BlinkHome()),
      ),
    );

    await tester.drag(find.byType(PageView), const Offset(-220, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('LIVE PREVIEW'), findsOneWidget);
  });

  // Pure static helpers only — no provider instance, so nothing here touches a
  // platform plugin and the group runs without a device.
  group('display brightness labelling', () {
    test('every preset level gets a distinct label', () {
      final labels = RobotStateProvider.brightnessLevels
          .map(RobotStateProvider.brightnessLabel)
          .toList();
      expect(labels, <String>['dim', 'medium', 'bright']);
    });

    test('the default level is one of the presets', () {
      expect(
        RobotStateProvider.brightnessLevels,
        contains(RobotStateProvider.defaultBrightness),
      );
    });

    test('levels are ordered, so cycling reads as getting brighter', () {
      const levels = RobotStateProvider.brightnessLevels;
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i], greaterThan(levels[i - 1]));
      }
    });

    test('a contrast restored from an older build still labels sensibly', () {
      // Values that were never in `brightnessLevels`: each must resolve to the
      // nearest level's name, which is what `cycleDisplayBrightness` also uses
      // to decide where to resume from.
      expect(RobotStateProvider.brightnessLabel(0), 'dim');
      expect(RobotStateProvider.brightnessLabel(200), 'medium');
      expect(RobotStateProvider.brightnessLabel(255), 'bright');
    });
  });

  group('touch sensitivity labelling', () {
    test('the three levels map to their own names', () {
      expect(RobotStateProvider.sensitivityLabel(0), 'low');
      expect(RobotStateProvider.sensitivityLabel(1), 'medium');
      expect(RobotStateProvider.sensitivityLabel(2), 'high');
    });

    test('an out-of-range level falls back to medium rather than throwing', () {
      expect(RobotStateProvider.sensitivityLabel(-1), 'medium');
      expect(RobotStateProvider.sensitivityLabel(99), 'medium');
    });

    test('the default level has a label', () {
      expect(
        RobotStateProvider.sensitivityLabel(
          RobotStateProvider.defaultSensitivity,
        ),
        'medium',
      );
    });
  });
}
