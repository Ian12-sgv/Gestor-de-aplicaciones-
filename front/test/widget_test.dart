import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:corporate_app_store/src/app.dart';

void main() {
  testWidgets('renders the corporate login shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CorporateApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('pdb Store'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Crear cuenta'), findsNothing);
    expect(find.text('Google'), findsNothing);
  });
}
