import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:rubric_desk/main.dart';

void main() {
  testWidgets('iOS uses Cupertino shell', (tester) async {
    await tester.pumpWidget(
      const RubricDeskApp(platformOverride: TargetPlatform.iOS),
    );
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
  });

  testWidgets('Android uses Material shell', (tester) async {
    await tester.pumpWidget(
      const RubricDeskApp(platformOverride: TargetPlatform.android),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CupertinoPageScaffold), findsNothing);
  });

  testWidgets('Windows uses Fluent shell', (tester) async {
    await tester.pumpWidget(
      const RubricDeskApp(platformOverride: TargetPlatform.windows),
    );
    expect(find.byType(fluent.FluentApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
  });
}
