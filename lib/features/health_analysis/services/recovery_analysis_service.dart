import 'heart_rate_analysis_service.dart';
import 'hrv_analysis_service.dart';
import 'sleep_analysis_service.dart';

enum RecoveryLevel { insufficient, normal, lighter, focus }

class RecoveryState {
  final RecoveryLevel level;
  final List<String> factors; // что отличается от привычного
  final List<String> used; // какие показатели участвовали
  final bool hrvUsed;
  final String recommendation;
  const RecoveryState(
      this.level, this.factors, this.used, this.hrvUsed, this.recommendation);
}

/// Самочувствие, указанное пользователем: 1 — хорошее, 2 — обычное, 3 — плохое.
/// Внутренняя экспериментальная оценка приложения, не медицинский показатель.
/// Один показатель вывода не даёт: «снизить интенсивность» — при двух совпавших признаках,
/// «уделить внимание восстановлению» — при трёх и более.
RecoveryState analyzeRecovery({
  required HeartAnalysis hr,
  required HrvAnalysis hrv,
  required SleepAnalysis sleep,
  required bool heavyLoadYesterday,
  int? feeling,
}) {
  final factors = <String>[];
  final used = <String>[];
  var signals = 0;
  var evaluable = 0;
  if (hr.baseline != null) {
    used.add('пульс в покое');
    evaluable++;
    if (hr.persistentHigh) {
      signals++;
      factors.add('пульс в покое выше привычного');
    }
  }
  final hrvUsed = hrv.available && hrv.baseline != null;
  if (hrvUsed) {
    used.add('HRV (${hrvMetricLabel(hrv.metric!)})');
    evaluable++;
    if (hrv.lowStreak) {
      signals++;
      factors.add('ночная HRV ниже личного диапазона');
    }
  }
  if (sleep.nights.isNotEmpty) {
    used.add('сон');
    evaluable++;
    if (sleep.shortStreak || sleep.lastNightShort) {
      signals++;
      factors.add(sleep.shortStreak
          ? 'несколько ночей сна короче порога'
          : 'короткий сон прошлой ночью');
    }
  }
  if (heavyLoadYesterday) {
    used.add('нагрузка');
    signals++;
    factors.add('вчера была повышенная нагрузка');
  }
  if (feeling == 3) {
    used.add('самочувствие');
    return RecoveryState(
        RecoveryLevel.focus,
        [...factors, 'самочувствие плохое по вашей оценке'],
        used,
        hrvUsed,
        'Вы отметили плохое самочувствие: сегодня лучше отдохнуть. Если оно не улучшается или есть '
        'тревожные симптомы, обратитесь к врачу.');
  }
  if (evaluable == 0) {
    return const RecoveryState(RecoveryLevel.insufficient, [], [], false,
        'Недостаточно данных для оценки восстановления: нужны пульс покоя, сон или HRV за 2–4 недели.');
  }
  if (signals >= 3) {
    return RecoveryState(
        RecoveryLevel.focus,
        factors,
        used,
        hrvUsed,
        'Несколько показателей отличаются от привычных. Уделите внимание сну и отдыху, '
        'выберите лёгкую активность. Если самочувствие ухудшается или изменения держатся, '
        'обсудите их с врачом.');
  }
  if (signals == 2) {
    return RecoveryState(
        RecoveryLevel.lighter,
        factors,
        used,
        hrvUsed,
        'Показатели восстановления отличаются от привычных. Рассмотрите более лёгкую тренировку '
        'и дополнительный отдых.');
  }
  return RecoveryState(RecoveryLevel.normal, factors, used, hrvUsed,
      'Заметных отклонений от привычного уровня нет. Обычная тренировка допустима, ориентируйтесь на самочувствие.');
}
