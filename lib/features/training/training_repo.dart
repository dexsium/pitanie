// Доступ к данным дневника силовых тренировок.
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/database.dart';
import 'strength_math.dart';

class EditSetData {
  final int reps;
  final double? weightKg;
  final int? restSec;
  const EditSetData(this.reps, this.weightKg, this.restSec);
}

class EditExerciseData {
  final int exerciseId;
  final List<EditSetData> sets;
  const EditExerciseData(this.exerciseId, this.sets);
}

class SessionSummary {
  final LiftSession session;
  final int exercises, sets, reps;
  final double volume;
  const SessionSummary(
      this.session, this.exercises, this.sets, this.reps, this.volume);
}

class TrainingRepo {
  final AppDatabase db;
  TrainingRepo(this.db);

  Future<List<LiftExercise>> exercises() =>
      (db.select(db.liftExercises)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<int> addExercise(String name, String kind) =>
      db.into(db.liftExercises).insert(LiftExercisesCompanion.insert(
          name: name.trim(), kind: Value(kind), isCustom: const Value(true)));

  Future<List<SessionSummary>> history({int limit = 200}) async {
    final sessions = await (db.select(db.liftSessions)
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
          ..limit(limit))
        .get();
    if (sessions.isEmpty) return const [];
    final sets = await (db.select(db.liftSets)
          ..where((t) => t.sessionId.isIn(sessions.map((s) => s.id).toList())))
        .get();
    final by = <int, List<LiftSet>>{};
    for (final s in sets) {
      by.putIfAbsent(s.sessionId, () => []).add(s);
    }
    return [
      for (final s in sessions)
        () {
          final l = by[s.id] ?? const <LiftSet>[];
          final data = [for (final x in l) SetData(x.reps, x.weightKg)];
          return SessionSummary(s, l.map((x) => x.exerciseId).toSet().length,
              l.length, totalReps(data), volumeKg(data));
        }()
    ];
  }

  Future<List<LiftSet>> setsOf(int sessionId) => (db.select(db.liftSets)
        ..where((t) => t.sessionId.equals(sessionId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.position),
          (t) => OrderingTerm.asc(t.setIndex)
        ]))
      .get();

  /// Сохраняет тренировку целиком в одной транзакции. [id] == null — новая.
  Future<int> save({
    int? id,
    required String title,
    required DateTime startedAt,
    required int? durationMin,
    required String note,
    required List<EditExerciseData> exercises,
  }) =>
      db.transaction(() async {
        late final int sid;
        if (id == null) {
          sid = await db.into(db.liftSessions).insert(
              LiftSessionsCompanion.insert(
                  startedAt: startedAt,
                  title: Value(title),
                  durationMin: Value(durationMin),
                  note: Value(note)));
        } else {
          sid = id;
          await (db.update(db.liftSessions)..where((t) => t.id.equals(sid)))
              .write(LiftSessionsCompanion(
                  startedAt: Value(startedAt),
                  title: Value(title),
                  durationMin: Value(durationMin),
                  note: Value(note)));
          await (db.delete(db.liftSets)..where((t) => t.sessionId.equals(sid)))
              .go();
        }
        for (var p = 0; p < exercises.length; p++) {
          final e = exercises[p];
          for (var i = 0; i < e.sets.length; i++) {
            final s = e.sets[i];
            await db.into(db.liftSets).insert(LiftSetsCompanion.insert(
                sessionId: sid,
                exerciseId: e.exerciseId,
                position: p,
                setIndex: i,
                reps: s.reps,
                weightKg: Value(s.weightKg),
                restSec: Value(s.restSec)));
          }
        }
        return sid;
      });

  Future<void> deleteSession(int id) async {
    await (db.delete(db.liftSets)..where((t) => t.sessionId.equals(id))).go();
    await (db.delete(db.liftSessions)..where((t) => t.id.equals(id))).go();
  }

  /// Подходы этого упражнения в последней предыдущей тренировке (подсказка «в прошлый раз»).
  Future<List<LiftSet>> lastSets(int exerciseId, {int? exceptSessionId}) async {
    final q = db.select(db.liftSets).join([
      innerJoin(
          db.liftSessions, db.liftSessions.id.equalsExp(db.liftSets.sessionId))
    ])
      ..where(db.liftSets.exerciseId.equals(exerciseId) &
          (exceptSessionId == null
              ? const Constant(true)
              : db.liftSessions.id.equals(exceptSessionId).not()))
      ..orderBy([OrderingTerm.desc(db.liftSessions.startedAt)]);
    final rows = await q.get();
    if (rows.isEmpty) return const [];
    final sid = rows.first.readTable(db.liftSets).sessionId;
    return rows
        .map((r) => r.readTable(db.liftSets))
        .where((s) => s.sessionId == sid)
        .toList()
      ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
  }

  /// Точки прогресса упражнения: по одной на тренировку, от старых к новым.
  Future<List<ExercisePoint>> progress(int exerciseId, DateTime from) async {
    final q = db.select(db.liftSets).join([
      innerJoin(
          db.liftSessions, db.liftSessions.id.equalsExp(db.liftSets.sessionId))
    ])
      ..where(db.liftSets.exerciseId.equals(exerciseId) &
          db.liftSessions.startedAt.isBiggerOrEqualValue(from))
      ..orderBy([OrderingTerm.asc(db.liftSessions.startedAt)]);
    final by = <int, List<SetData>>{};
    final dates = <int, DateTime>{};
    for (final r in await q.get()) {
      final s = r.readTable(db.liftSets);
      final se = r.readTable(db.liftSessions);
      by.putIfAbsent(se.id, () => []).add(SetData(s.reps, s.weightKg));
      dates[se.id] = se.startedAt;
    }
    return [
      for (final e in by.entries) exercisePoint(dates[e.key]!, e.value),
    ]..sort((a, b) => a.date.compareTo(b.date));
  }

  // ---------- шаблоны ----------
  Future<List<LiftTemplate>> templates() => db.select(db.liftTemplates).get();

  Future<void> saveTemplate(String name, List<int> exerciseIds) =>
      db.into(db.liftTemplates).insert(LiftTemplatesCompanion.insert(
          name: name, exerciseIds: jsonEncode(exerciseIds)));

  Future<void> deleteTemplate(int id) =>
      (db.delete(db.liftTemplates)..where((t) => t.id.equals(id))).go();

  static List<int> templateIds(LiftTemplate t) {
    try {
      return [for (final x in jsonDecode(t.exerciseIds) as List) x as int];
    } catch (_) {
      return const [];
    }
  }
}
