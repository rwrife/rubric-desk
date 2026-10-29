import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rubric_desk/domain/database.dart';
import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';
import 'package:rubric_desk/scoring_workspace.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final db = SqliteLedgerDatabase.open(
    '${dir.path}${Platform.pathSeparator}rubric-desk.sqlite',
  );
  runApp(RubricDeskApp(store: db));
}

class RubricDeskApp extends StatelessWidget {
  const RubricDeskApp({super.key, this.platformOverride, this.store});

  final TargetPlatform? platformOverride;
  final SqliteLedgerDatabase? store;

  @override
  Widget build(BuildContext context) {
    final platform = platformOverride ?? defaultTargetPlatform;
    final page = AuthoringPage(
      store: store ?? SqliteLedgerDatabase.inMemory(),
      platform: platform,
    );
    switch (platform) {
      case TargetPlatform.windows:
        return fluent.FluentApp(
          title: 'Rubric Desk',
          home: fluent.NavigationView(
            content: fluent.ScaffoldPage(
              header: const fluent.PageHeader(title: Text('Rubric Desk')),
              content: page,
            ),
          ),
        );
      case TargetPlatform.iOS:
        return CupertinoApp(
          title: 'Rubric Desk',
          home: CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(
              middle: Text('Rubric Desk'),
            ),
            child: SafeArea(child: page),
          ),
        );
      default:
        return MaterialApp(
          title: 'Rubric Desk',
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            appBar: AppBar(title: const Text('Rubric Desk')),
            body: page,
          ),
        );
    }
  }
}

class AuthoringPage extends StatefulWidget {
  const AuthoringPage({super.key, required this.store, required this.platform});
  final SqliteLedgerDatabase store;
  final TargetPlatform platform;

  @override
  State<AuthoringPage> createState() => _AuthoringPageState();
}

class _AuthoringPageState extends State<AuthoringPage> {
  String? courseId;
  String? studentId;
  String? rubricId;
  String? criterionId;
  String? error;
  final title = TextEditingController();
  final student = TextEditingController();
  final rubricTitle = TextEditingController();
  final criterion = TextEditingController();
  final weight = TextEditingController(text: '1');
  final levels = TextEditingController(text: 'Needs work:0, Meets:1');
  final bands = TextEditingController();
  final assignment = TextEditingController();
  final criteria = <Criterion>[];
  String? backupMessage;

  @override
  void dispose() {
    for (final c in [
      title,
      student,
      rubricTitle,
      criterion,
      weight,
      levels,
      bands,
      assignment,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void save(VoidCallback action) {
    try {
      action();
      setState(() => error = null);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> shareBackup() async {
    try {
      final data = utf8.encode(widget.store.exportBackup());
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              data,
              mimeType: 'application/json',
              name: 'rubric-desk-backup.json',
            ),
          ],
          subject: 'Rubric Desk backup',
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> restoreBackup() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.length > 25 * 1024 * 1024) {
        throw const FormatException('Backup must be at most 25 MB');
      }
      final raw = utf8.decode(bytes);
      final counts = widget.store.previewBackup(raw);
      if (!mounted) return;
      final summary =
          'Preview: ${counts['courses']} courses, ${counts['students']} students, '
          '${counts['rubrics']} rubric revisions, ${counts['assignments']} assignments, '
          '${counts['mark_ledger']} marks. Current data will be replaced.';
      final confirmed = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Restore backup confirmation',
        pageBuilder: (ctx, _, _) {
          if (widget.platform == TargetPlatform.iOS) {
            return CupertinoAlertDialog(
              title: const Text('Replace local data?'),
              content: Text(summary),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Restore'),
                ),
              ],
            );
          }
          if (widget.platform == TargetPlatform.windows) {
            return fluent.ContentDialog(
              title: const Text('Replace local data?'),
              content: Text(summary),
              actions: [
                fluent.Button(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                fluent.Button(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Restore'),
                ),
              ],
            );
          }
          return AlertDialog(
            title: const Text('Replace local data?'),
            content: Text(summary),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Restore'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      widget.store.restoreBackup(raw);
      if (mounted) {
        setState(() {
          courseId = null;
          rubricId = null;
          studentId = null;
          backupMessage = 'Backup restored';
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  String id() => const Uuid().v4();

  // ponytail: comma-delimited levels/bands keep editing keyboard-friendly;
  // add structured row editors if teachers need commas inside labels.
  List<Level> parsedLevels() => levels.text.split(',').map((part) {
    final bits = part.trim().split(':');
    if (bits.length != 2 || bits[0].trim().isEmpty) {
      throw const FormatException('Levels: Label:points, Label:points');
    }
    return Level(
      id: id(),
      label: bits[0].trim(),
      points: int.parse(bits[1].trim()),
    );
  }).toList();

  List<Band> parsedBands() => bands.text.trim().isEmpty
      ? []
      : bands.text.split(',').map((part) {
          final bits = part.trim().split(':');
          if (bits.length != 2 || bits[1].trim().isEmpty) {
            throw const FormatException('Bands: minimum percent:label');
          }
          return Band(
            minimumPercent: int.parse(bits[0].trim()),
            label: bits[1].trim(),
          );
        }).toList();

  Widget field(String label, TextEditingController controller) {
    if (widget.platform == TargetPlatform.windows) {
      return fluent.InfoLabel(
        label: label,
        child: fluent.TextBox(controller: controller, placeholder: label),
      );
    }
    if (widget.platform == TargetPlatform.iOS) {
      return Semantics(
        label: label,
        textField: true,
        child: CupertinoTextField(
          controller: controller,
          placeholder: label,
          padding: const EdgeInsets.all(12),
        ),
      );
    }
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget button(String label, VoidCallback onPressed) {
    if (widget.platform == TargetPlatform.windows) {
      return fluent.Button(onPressed: onPressed, child: Text(label));
    }
    if (widget.platform == TargetPlatform.iOS) {
      return CupertinoButton(onPressed: onPressed, child: Text(label));
    }
    return FilledButton(onPressed: onPressed, child: Text(label));
  }

  Widget heading(String label) => Semantics(
    header: true,
    child: Text(
      label,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final courses = widget.store.courses;
    final rubrics = widget.store.latestRubrics;
    final active = rubrics.where((r) => r.id == rubricId).firstOrNull;
    final content = ListView(
      children:
          [
                heading('Local data'),
                button('Share JSON backup', shareBackup),
                button('Restore JSON backup', restoreBackup),
                if (backupMessage != null) Text(backupMessage!),
                heading('Courses'),
                for (final c in courses)
                  button(
                    '${c.label}${c.id == courseId ? " (selected)" : ""}',
                    () => setState(() {
                      courseId = c.id;
                      studentId = null;
                      student.clear();
                      title.text = c.label;
                    }),
                  ),
                button(
                  'New course',
                  () => setState(() {
                    courseId = null;
                    studentId = null;
                    title.clear();
                    student.clear();
                  }),
                ),
                field('Course name', title),
                button(
                  courseId == null ? 'Create course' : 'Save course name',
                  () => save(() {
                    final key = courseId ?? id();
                    widget.store.saveCourse(key, title.text);
                    courseId = key;
                  }),
                ),
                if (courseId != null) ...[
                  heading('Roster'),
                  for (final s in widget.store.students(courseId!))
                    button(
                      '${s.label}${s.id == studentId ? " (selected)" : ""}',
                      () => setState(() {
                        studentId = s.id;
                        student.text = s.label;
                      }),
                    ),
                  button(
                    'New student',
                    () => setState(() {
                      studentId = null;
                      student.clear();
                    }),
                  ),
                  field('Student local label', student),
                  button(
                    studentId == null ? 'Add student' : 'Save student name',
                    () => save(() {
                      final key = studentId ?? id();
                      widget.store.saveStudent(key, courseId!, student.text);
                      studentId = key;
                    }),
                  ),
                ],
                heading('Rubrics'),
                button(
                  'New rubric',
                  () => setState(() {
                    rubricId = null;
                    criterionId = null;
                    rubricTitle.clear();
                    criterion.clear();
                    bands.clear();
                    criteria.clear();
                  }),
                ),
                for (final r in rubrics)
                  button(
                    '${r.title} (revision ${r.revision})',
                    () => setState(() {
                      rubricId = r.id;
                      criterionId = null;
                      rubricTitle.text = r.title;
                      criteria
                        ..clear()
                        ..addAll(r.criteria);
                      bands.text = r.bands
                          .map((b) => '${b.minimumPercent}:${b.label}')
                          .join(', ');
                    }),
                  ),
                field('Rubric title', rubricTitle),
                heading('Criteria preview'),
                for (final c in criteria)
                  button(
                    '${c.name} · weight ${c.weight} · ${c.levels.map((l) => '${l.label} ${l.points}').join(', ')}',
                    () => setState(() {
                      criterionId = c.id;
                      criterion.text = c.name;
                      weight.text = '${c.weight}';
                      levels.text = c.levels
                          .map((l) => '${l.label}:${l.points}')
                          .join(', ');
                    }),
                  ),
                if (criterionId != null)
                  button(
                    'Remove selected criterion',
                    () => setState(() {
                      criteria.removeWhere((c) => c.id == criterionId);
                      criterionId = null;
                      criterion.clear();
                    }),
                  ),
                if (criterionId != null)
                  button(
                    'New criterion instead',
                    () => setState(() {
                      criterionId = null;
                      criterion.clear();
                    }),
                  ),
                field('Criterion name', criterion),
                field('Integer weight', weight),
                field('Ordered levels (Label:points, Label:points)', levels),
                button(
                  criterionId == null ? 'Add criterion' : 'Update criterion',
                  () => save(() {
                    final previous = criteria
                        .where((c) => c.id == criterionId)
                        .firstOrNull;
                    final entered = parsedLevels();
                    // Preserve level IDs when editing labels/points at same positions.
                    final updated = [
                      for (var i = 0; i < entered.length; i++)
                        Level(
                          id: previous != null && i < previous.levels.length
                              ? previous.levels[i].id
                              : entered[i].id,
                          label: entered[i].label,
                          points: entered[i].points,
                        ),
                    ];
                    final next = Criterion(
                      id: criterionId ?? id(),
                      name: criterion.text.trim(),
                      weight: int.parse(weight.text),
                      levels: updated,
                    );
                    Rubric(
                      id: id(),
                      revision: 1,
                      title: 'Preview',
                      criteria: [next],
                    );
                    final index = criteria.indexWhere(
                      (c) => c.id == criterionId,
                    );
                    if (index < 0) {
                      criteria.add(next);
                    } else {
                      criteria[index] = next;
                    }
                    criterionId = null;
                    criterion.clear();
                  }),
                ),
                field('Optional bands (minimum percent:label)', bands),
                button(
                  active == null ? 'Publish rubric' : 'Publish new revision',
                  () => save(() {
                    final r = Rubric(
                      id: rubricId ?? id(),
                      revision: active == null ? 1 : active.revision + 1,
                      title: rubricTitle.text,
                      criteria: criteria,
                      bands: parsedBands(),
                    );
                    widget.store.saveRubricRevision(r);
                    rubricId = r.id;
                  }),
                ),
                if (courseId != null && active != null) ...[
                  heading('Assignments'),
                  for (final a in widget.store.assignments(courseId!))
                    button(
                      '${a.title} · revision ${a.rubricRevision} · Score',
                      () {
                        Navigator.of(context).push(
                          platformRoute(
                            widget.platform,
                            ScoringWorkspaceLayout(
                              store: widget.store,
                              assignment: a,
                              platform: widget.platform,
                            ),
                          ),
                        );
                      },
                    ),
                  field('Assignment title', assignment),
                  button(
                    'Create assignment pinned to revision ${active.revision}',
                    () => save(() {
                      if (assignment.text.trim().isEmpty) {
                        throw const FormatException(
                          'Assignment title required',
                        );
                      }
                      widget.store.createAssignment(
                        Assignment(
                          id: id(),
                          courseId: courseId!,
                          title: assignment.text.trim(),
                          rubricId: active.id,
                          rubricRevision: active.revision,
                          createdAt: DateTime.now(),
                        ),
                      );
                      assignment.clear();
                    }),
                  ),
                ],
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xffc22730)),
                    ),
                  ),
              ]
              .map(
                (w) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: w,
                ),
              )
              .toList(),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Padding(padding: const EdgeInsets.all(16), child: content),
      ),
    );
  }
}
