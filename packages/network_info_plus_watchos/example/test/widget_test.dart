import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:network_info_plus_example/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const NetworkInfoPlusExampleApp());
    expect(find.text('Running on Apple Watch'), findsOneWidget);
  });
}
