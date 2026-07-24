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
    expect(find.text('MAPPED TO 128 × 64 OLED'), findsOneWidget);
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
}
