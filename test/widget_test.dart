// Basic smoke test: the app root builds without throwing.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nkapsave/main.dart';

void main() {
  testWidgets('App root builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: NkapSaveApp()));
    expect(find.byType(NkapSaveApp), findsOneWidget);
  });
}
