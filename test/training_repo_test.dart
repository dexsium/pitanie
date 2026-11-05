import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/settings/backup_service.dart';
import 'package:pitanie/features/training/training_repo.dart';

void main() {
  late AppDatabase db;
  late TrainingRepo repo;

  setUp(() async {
    db = AppDatabase.memory();
    repo = TrainingRepo(db);
    await db.seedLiftExercises();
  });
  tearDown(() => db.close());

  test('базовые упражнения создаются один раз', () async {
    final n = (await repo.exercises()).length;
    expect(n, greaterThan(10));
    await db.seedLiftExercises();
    expect((await repo.exercises()).length, n);
  });

  test('сохранение, история, прогресс и правка тренировки', () async {
    final ex = (await repo.exercises()).first;
    final id = await repo.save(
        title: 'Грудь',
        startedAt: DateTime.now().subtract(const Duration(days: 2)),
        durationMin: 50,
        note: '',
        exercises: [
          EditExerciseData(ex.id, const [
            EditSetData(5, 100, 120),
            EditSetData(5, 90, null),
          ])
        ]);
    var h = await repo.history();
    expect(h.length, 1);
    expect(h.first.sets, 2);
    expect(h.first.volume, 950);

    final pts = await repo.progress(
        ex.id, DateTime.now().subtract(const Duration(days: 30)));
    expect(pts.length, 1);
    expect(pts.first.maxWeight, 100);

    // Правка заменяет подходы, а не дублирует их.
    await repo.save(
        id: id,
        title: 'Грудь',
        startedAt: DateTime.now().subtract(const Duration(days: 2)),
        durationMin: 50,
        note: '',
        exercises: [
          EditExerciseData(ex.id, const [EditSetData(8, 60, null)])
        ]);
    h = await repo.history();
    expect(h.length, 1);
    expect(h.first.sets, 1);

    final last = await repo.lastSets(ex.id);
    expect(last.single.reps, 8);

    await repo.deleteSession(id);
    expect(await repo.history(), isEmpty);
  });

  test('шаблон сохраняет порядок упражнений', () async {
    final ex = await repo.exercises();
    await repo.saveTemplate('Верх', [ex[2].id, ex[0].id]);
    final t = (await repo.templates()).single;
    expect(TrainingRepo.templateIds(t), [ex[2].id, ex[0].id]);
  });

  test('резервная копия содержит и восстанавливает дневник тренировок',
      () async {
    final ex = (await repo.exercises()).first;
    await repo.save(
        title: 'Тест',
        startedAt: DateTime(2026, 11, 1, 10),
        durationMin: 30,
        note: '',
        exercises: [
          EditExerciseData(ex.id, const [EditSetData(10, 50, null)])
        ]);
    final json = await BackupService(db).exportJson();
    await repo.deleteSession((await repo.history()).single.session.id);
    expect(await repo.history(), isEmpty);
    await BackupService(db).restore(json);
    final h = await repo.history();
    expect(h.single.sets, 1);
    expect(h.single.volume, 500);
  });
}
