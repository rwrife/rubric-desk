import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:share_plus/share_plus.dart';
import 'package:rubric_desk/domain/exports.dart';
import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';
import 'package:rubric_desk/domain/database.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';

Route<T> platformRoute<T>(TargetPlatform platform, Widget page) =>
    platform == TargetPlatform.iOS
    ? CupertinoPageRoute<T>(builder: (_) => page)
    : platform == TargetPlatform.windows
    ? fluent.FluentPageRoute<T>(builder: (_) => page)
    : material.MaterialPageRoute<T>(builder: (_) => page);

class ScoringWorkspaceLayout extends StatefulWidget {
  const ScoringWorkspaceLayout({
    super.key,
    required this.store,
    required this.assignment,
    required this.platform,
  });

  final SqliteLedgerDatabase store;
  final Assignment assignment;
  final TargetPlatform platform;

  @override
  State<ScoringWorkspaceLayout> createState() => _ScoringWorkspaceLayoutState();
}

class _ScoringWorkspaceLayoutState extends State<ScoringWorkspaceLayout> {
  late final Rubric rubric = widget.store.getRubricRevision(
    widget.assignment.rubricId,
    widget.assignment.rubricRevision,
  )!;
  late final students = widget.store.students(widget.assignment.courseId);
  String? studentId;
  String? criterionId;
  final focus = FocusNode();
  final note = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    studentId = students.firstOrNull?.id;
    criterionId = rubric.criteria.first.id;
  }

  @override
  void dispose() {
    focus.dispose();
    note.dispose();
    super.dispose();
  }

  StudentScore score(String id) =>
      widget.store.score(assignmentId: widget.assignment.id, studentId: id);

  String total(StudentScore s) {
    if (s.allExcused) return 'All excused · no total';
    if (s.incomplete) return 'Incomplete · no total';
    return '${s.percent}%${s.band == null ? '' : ' · ${s.band}'}'
        '${s.excusedWeight == 0 ? '' : ' · ${s.excusedCriteria.length} excused'}';
  }

  void record(MarkKind kind, {String? levelId}) {
    if (studentId == null || criterionId == null) return;
    try {
      widget.store.appendMark(
        assignmentId: widget.assignment.id,
        studentId: studentId!,
        criterionId: criterionId!,
        kind: kind,
        levelId: levelId,
        note: note.text,
      );
      setState(() => error = null);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  // Undo is another ledger fact; it never removes history. Repeated undo of
  // an undo is deliberately not supported; use explicit mark controls instead.
  void undo() {
    if (studentId == null) return;
    final trail = widget.store
        .auditTrail(widget.assignment.id)
        .where((e) => e.studentId == studentId && !e.note.startsWith('Undo:'))
        .toList();
    if (trail.isEmpty) return;
    final last = trail.last;
    final previous = trail
        .where(
          (e) =>
              e.criterionId == last.criterionId && e.sequence < last.sequence,
        )
        .lastOrNull;
    setState(() => criterionId = last.criterionId);
    try {
      widget.store.appendMark(
        assignmentId: widget.assignment.id,
        studentId: studentId!,
        criterionId: last.criterionId,
        kind: previous?.kind ?? MarkKind.unmarked,
        levelId: previous?.levelId,
        note: 'Undo: ${last.sequence}',
      );
      setState(() => error = null);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  void key(KeyEvent e) {
    if (e is! KeyDownEvent || studentId == null) return;
    final c = rubric.criterion(criterionId!);
    final digit = int.tryParse(e.character ?? '');
    if (digit != null && digit < c.levels.length) {
      record(MarkKind.level, levelId: c.levels[digit].id);
    } else if (e.logicalKey == LogicalKeyboardKey.keyE) {
      record(MarkKind.excused);
    } else if (e.logicalKey == LogicalKeyboardKey.keyU ||
        e.logicalKey == LogicalKeyboardKey.delete) {
      record(MarkKind.unmarked);
    } else if (e.logicalKey == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      undo();
    } else {
      final col = rubric.criteria.indexWhere((x) => x.id == criterionId);
      final row = students.indexWhere((x) => x.id == studentId);
      if (e.logicalKey == LogicalKeyboardKey.arrowRight &&
          col + 1 < rubric.criteria.length) {
        setState(() => criterionId = rubric.criteria[col + 1].id);
      } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft && col > 0) {
        setState(() => criterionId = rubric.criteria[col - 1].id);
      } else if (e.logicalKey == LogicalKeyboardKey.arrowDown &&
          row + 1 < students.length) {
        setState(() => studentId = students[row + 1].id);
      } else if (e.logicalKey == LogicalKeyboardKey.arrowUp && row > 0) {
        setState(() => studentId = students[row - 1].id);
      }
    }
  }

  Widget button(String label, VoidCallback action, {Key? key}) {
    switch (widget.platform) {
      case TargetPlatform.iOS:
        return CupertinoButton(key: key, onPressed: action, child: Text(label));
      case TargetPlatform.windows:
        return fluent.Button(key: key, onPressed: action, child: Text(label));
      default:
        return material.FilledButton(
          key: key,
          onPressed: action,
          child: Text(label),
        );
    }
  }

  Widget noteField() {
    switch (widget.platform) {
      case TargetPlatform.iOS:
        return CupertinoTextField(
          key: const Key('mark-note'),
          controller: note,
          placeholder: 'Evidence note (optional)',
        );
      case TargetPlatform.windows:
        return fluent.TextBox(
          key: const Key('mark-note'),
          controller: note,
          placeholder: 'Evidence note (optional)',
        );
      default:
        return material.TextField(
          key: const Key('mark-note'),
          controller: note,
          decoration: const material.InputDecoration(
            labelText: 'Evidence note (optional)',
          ),
        );
    }
  }

  Widget inspector() {
    if (studentId == null) return const Text('No students in course roster');
    final s = score(studentId!);
    final c = rubric.criterion(criterionId!);
    final b = s.breakdown.firstWhere((x) => x.criterion.id == c.id);
    final current = b.unmarked
        ? 'Unmarked (unknown)'
        : b.excused
        ? 'Excused · excluded from denominator'
        : '${b.earned}/${c.maximumPoints} points';
    return SingleChildScrollView(
      key: const Key('score-inspector'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            students.firstWhere((x) => x.id == studentId).label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Semantics(
            liveRegion: true,
            child: Text(total(s), key: const Key('score-total')),
          ),
          Text(
            'Counted weight ${s.countedWeight}; excused weight ${s.excusedWeight}',
          ),
          const SizedBox(height: 16),
          Text(
            '${c.name} · weight ${c.weight}',
            style: const TextStyle(fontSize: 18),
          ),
          Text(current, key: const Key('mark-status')),
          noteField(),
          for (var i = 0; i < c.levels.length; i++)
            button(
              '$i: ${c.levels[i].label} (${c.levels[i].points})',
              () => record(MarkKind.level, levelId: c.levels[i].id),
              key: Key('level-$i'),
            ),
          button(
            'Excuse',
            () => record(MarkKind.excused),
            key: const Key('excuse'),
          ),
          button(
            'Clear to unmarked',
            () => record(MarkKind.unmarked),
            key: const Key('unmark'),
          ),
          button('Undo last mark', undo, key: const Key('undo-mark')),
          const SizedBox(height: 16),
          button('Share feedback', () {
            if (studentId == null) return;
            final s = students.firstWhere((x) => x.id == studentId);
            final text = feedbackText(
              s.label,
              widget.assignment,
              score(studentId!),
            );
            SharePlus.instance.share(
              ShareParams(
                text: text,
                subject: '${widget.assignment.title} - ${s.label}',
              ),
            );
          }, key: const Key('share-feedback')),
          button('Share grade CSV', () {
            final rows = [
              for (final s in students) (label: s.label, score: score(s.id)),
            ];
            final csv = gradeCsv(widget.assignment, rows);
            SharePlus.instance.share(
              ShareParams(
                files: [
                  XFile.fromData(
                    utf8.encode(csv),
                    mimeType: 'text/csv',
                    name: '${widget.assignment.title}-grades.csv',
                  ),
                ],
                subject: '${widget.assignment.title} grades',
              ),
            );
          }, key: const Key('share-csv')),
          button('Share printable rubric', () {
            SharePlus.instance.share(
              ShareParams(
                text: printableRubric(rubric),
                subject: '${rubric.title} (rev ${rubric.revision})',
              ),
            );
          }, key: const Key('share-rubric')),
          const SizedBox(height: 16),
          const Text('Breakdown', style: TextStyle(fontSize: 18)),
          for (final part in s.breakdown)
            Text(
              '${part.criterion.name} · weight ${part.criterion.weight}: '
              '${part.unmarked
                  ? 'unmarked'
                  : part.excused
                  ? 'excused'
                  : '${part.earned}/${part.criterion.maximumPoints}'}'
              '${part.mark?.note.isNotEmpty == true ? ' · ${part.mark!.note}' : ''}',
            ),
          if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        ],
      ),
    );
  }

  Widget roster(bool desktop) => ListView(
    key: Key(desktop ? 'desktop-grid' : 'tablet-grid'),
    children: [
      for (final s in students)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            button(
              '${s.label}: ${total(score(s.id))}',
              () => setState(() => studentId = s.id),
              key: Key('student-${s.id}'),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in rubric.criteria)
                    button('${c.name}: ${cell(score(s.id), c)}', () {
                      setState(() {
                        studentId = s.id;
                        criterionId = c.id;
                      });
                    }, key: Key('cell-${s.id}-${c.id}')),
                ],
              ),
            ),
          ],
        ),
    ],
  );

  String cell(StudentScore s, Criterion c) {
    final b = s.breakdown.firstWhere((x) => x.criterion.id == c.id);
    return b.unmarked
        ? 'Unmarked'
        : b.excused
        ? 'Excused'
        : '${b.earned}/${c.maximumPoints}';
  }

  Widget phone() => Column(
    children: [
      if (students.isNotEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in students)
                button(
                  s.label,
                  () => setState(() => studentId = s.id),
                  key: Key('student-${s.id}'),
                ),
            ],
          ),
        ),
      if (studentId != null)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in rubric.criteria)
                button(
                  c.name,
                  () => setState(() => criterionId = c.id),
                  key: Key('criterion-${c.id}'),
                ),
            ],
          ),
        ),
      Expanded(child: inspector()),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final body = KeyboardListener(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: key,
      child: width < 600
          ? phone()
          : width < 1000
          ? Column(
              children: [
                Expanded(child: roster(false)),
                SizedBox(height: 300, child: inspector()),
              ],
            )
          : Row(
              children: [
                Expanded(child: roster(true)),
                SizedBox(width: 360, child: inspector()),
              ],
            ),
    );
    switch (widget.platform) {
      case TargetPlatform.iOS:
        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: Text(widget.assignment.title),
          ),
          child: SafeArea(child: body),
        );
      case TargetPlatform.windows:
        return fluent.ScaffoldPage(
          header: fluent.PageHeader(title: Text(widget.assignment.title)),
          content: body,
        );
      default:
        return material.Scaffold(
          appBar: material.AppBar(title: Text(widget.assignment.title)),
          body: SafeArea(child: body),
        );
    }
  }
}
