// Basic smoke tests for CNC Partner.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cnc_partner/widgets/phone_field.dart';

void main() {
  test('country dial codes are configured', () {
    expect(kCountries, isNotEmpty);
    expect(kCountries.first.dial, '+971');
    expect(kCountries.every((c) => c.dial.startsWith('+')), isTrue);
  });

  testWidgets('PhoneField renders and shows the default dial code',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PhoneField(onChanged: (_) {}),
      ),
    ));
    expect(find.text('+971'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
