import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_secure_storage_example/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const FlutterSecureStorageExampleApp());
    expect(find.text('Running on Apple Watch'), findsOneWidget);
  });
}
