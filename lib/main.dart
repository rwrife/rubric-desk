import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const RubricDeskApp());

// ponytail: landing shell only; add adaptive controls as workflows land.
class RubricDeskApp extends StatelessWidget {
  const RubricDeskApp({super.key, this.platformOverride});

  final TargetPlatform? platformOverride;

  @override
  Widget build(BuildContext context) {
    switch (platformOverride ?? defaultTargetPlatform) {
      case TargetPlatform.windows:
        return const fluent.FluentApp(
          title: 'Rubric Desk',
          home: fluent.NavigationView(
            content: fluent.ScaffoldPage(
              header: fluent.PageHeader(title: Text('Rubric Desk')),
              content: Center(child: Text('Rubric Desk — offline workspace')),
            ),
          ),
        );
      case TargetPlatform.iOS:
        return const CupertinoApp(
          title: 'Rubric Desk',
          home: CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text('Rubric Desk')),
            child: SafeArea(
              child: Center(child: Text('Rubric Desk — offline workspace')),
            ),
          ),
        );
      default:
        return MaterialApp(
          title: 'Rubric Desk',
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            appBar: AppBar(title: const Text('Rubric Desk')),
            body: const Center(child: Text('Rubric Desk — offline workspace')),
          ),
        );
    }
  }
}
