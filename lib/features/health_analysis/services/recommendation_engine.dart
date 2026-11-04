import '../domain/models/health_models.dart';
import 'heart_rate_analysis_service.dart';
import 'hrv_analysis_service.dart';
import 'recovery_analysis_service.dart';
import 'sleep_analysis_service.dart';
import 'spo2_analysis_service.dart';

class HealthResults {
  final HeartAnalysis hr;
  final HrvAnalysis hrv;
  final SleepAnalysis sleep;
  final Spo2Analysis spo2;
  final RecoveryState recovery;
  const HealthResults(this.hr, this.hrv, this.sleep, this.spo2, this.recovery);
}

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _n(double v) => v.round().toString();

/// Детерминированные правила → выводы с основанием. Текст формулирует правило, не генеративная
/// модель. Ключ события включает дату последних данных, поэтому повторный запуск на тех же
/// данных даёт тот же ключ (дубль не создаётся).
List<Insight> buildInsights(HealthResults r, DateTime now) {
  final out = <Insight>[];
  final hr = r.hr;
  if (hr.persistentHigh && hr.baseline != null && hr.lastDay != null) {
    final vals = hr.recent.map((e) => _n(e.v)).join(', ');
    out.add(Insight(
      key: 'hr_high:${_d(hr.lastDay!)}',
      category: HealthCategory.heartRate,
      severity: Severity.attention,
      title: 'Пульс в покое выше привычного',
      body:
          'Ваш пульс в покое несколько дней выше привычного уровня (обычно около '
          '${_n(hr.baseline!.median)}, последние дни: $vals уд/мин). Проверьте качество сна, нагрузку '
          'и самочувствие. Если изменение сохраняется, обсудите его с врачом.',
      basis: const ['пульс в покое (расчёт по данным часов)'],
      period: 'последние 3 дня против ${hr.baseline!.n} дней нормы',
      confidence: hr.baseline!.n >= 21 ? 'средняя' : 'низкая',
      createdAt: now,
    ));
  } else if (hr.weekDelta != null &&
      hr.weekDelta!.abs() >= 3 &&
      hr.lastDay != null) {
    final dir = hr.weekDelta! < 0 ? 'ниже' : 'выше';
    out.add(Insight(
      key: 'hr_week:${_d(hr.lastDay!)}',
      category: HealthCategory.heartRate,
      severity: Severity.info,
      title: 'Изменение пульса в покое за неделю',
      body:
          'За последнюю неделю пульс в покое стал $dir на ${_n(hr.weekDelta!.abs())} уд/мин '
          'по сравнению с предыдущей. Это только изменение относительно предыдущего периода, '
          'само по себе оно не означает ни улучшения, ни ухудшения.',
      basis: const ['пульс в покое (расчёт по данным часов)'],
      period: '7 дней против предыдущих 7',
      confidence: 'низкая',
      createdAt: now,
    ));
  }

  final h = r.hrv;
  if (h.lowStreak && h.baseline != null && h.metric != null) {
    final t = hrvMetricLabel(h.metric!);
    out.add(Insight(
      key: 'hrv_low:${_d(now)}:$t',
      category: HealthCategory.hrv,
      severity: Severity.advice,
      title: 'Ночная HRV ниже привычного диапазона',
      body: 'Несколько ночей подряд HRV ($t) ниже вашего обычного диапазона '
          '(медиана ${_n(h.baseline!.median)} мс). Это не диагноз: на HRV влияют сон, нагрузка, '
          'алкоголь, недомогание и многое другое. Понаблюдайте за самочувствием.',
      basis: ['HRV ($t)'],
      period: '3 ночи против ${h.baseline!.n} ночей нормы',
      confidence: h.baseline!.n >= 21 ? 'средняя' : 'низкая',
      createdAt: now,
    ));
  }

  final s = r.sleep;
  if (s.shortStreak && s.nights.isNotEmpty) {
    out.add(Insight(
      key: 'sleep_streak:${_d(s.nights.last.day)}',
      category: HealthCategory.sleep,
      severity: Severity.advice,
      title: 'Несколько ночей короткого сна',
      body:
          'Последние три ночи продолжительность сна ниже вашего порога. Постарайтесь выделить '
          'больше времени на отдых. Стадии сна определены часами приблизительно.',
      basis: const ['продолжительность сна'],
      period: 'последние 3 ночи',
      confidence: 'средняя',
      createdAt: now,
    ));
  } else if (s.irregular && s.irregularityMin != null && s.nights.isNotEmpty) {
    out.add(Insight(
      key: 'sleep_irregular:${_d(s.nights.last.day)}',
      category: HealthCategory.sleep,
      severity: Severity.info,
      title: 'Нерегулярное время засыпания',
      body:
          'За последнюю неделю время засыпания заметно менялось (разброс около '
          '${_n(s.irregularityMin!)} мин). Более стабильный режим обычно помогает восстановлению.',
      basis: const ['время начала сна'],
      period: 'последние 7 ночей',
      confidence: 'средняя',
      createdAt: now,
    ));
  }

  final o = r.spo2;
  switch (o.level) {
    case Spo2Level.repeatedVeryLow:
      out.add(Insight(
        key: 'spo2_vlow:${_d(now)}',
        category: HealthCategory.spo2,
        severity: Severity.urgent,
        title: 'Повторные очень низкие значения SpO₂',
        body:
            'Часы несколько раз за сутки показали очень низкую сатурацию. Часы могут ошибаться '
            '(движение, посадка), поэтому измерьте подходящим медицинским прибором. При одышке, боли '
            'в груди, спутанности сознания или плохом самочувствии немедленно вызовите скорую помощь. '
            'Не полагайтесь только на часы.',
        basis: ['SpO₂ (${o.lowCount} значений ≤ 88 % за 24 ч)'],
        period: 'последние 24 часа',
        confidence: 'низкая (измерения часов)',
        createdAt: now,
      ));
    case Spo2Level.repeatedLow:
      out.add(Insight(
        key: 'spo2_low:${_d(now)}',
        category: HealthCategory.spo2,
        severity: Severity.attention,
        title: 'Повторные низкие значения SpO₂',
        body:
            'За последние дни несколько измерений SpO₂ ниже 92 %. Это может быть ошибкой датчика. '
            'Проверьте подходящим медицинским прибором и, если значения подтверждаются или есть '
            'симптомы, обратитесь к врачу. При тяжёлых симптомах вызовите скорую помощь.',
        basis: ['SpO₂ (${o.lowCount} значений < 92 % за 3 суток)'],
        period: 'последние 3 суток',
        confidence: 'низкая (измерения часов)',
        createdAt: now,
      ));
    case Spo2Level.repeatMeasure:
      out.add(Insight(
        key: 'spo2_repeat:${_d(now)}',
        category: HealthCategory.spo2,
        severity: Severity.info,
        title: 'Повторите измерение SpO₂',
        body:
            'Последнее значение SpO₂ оказалось низким, но одно измерение ничего не доказывает: '
            'на него влияют движение и посадка часов. Повторите измерение в покое.',
        basis: const ['SpO₂ (одно измерение)'],
        period: 'последние 24 часа',
        confidence: 'низкая',
        createdAt: now,
      ));
    case Spo2Level.normal:
      break;
  }

  final rec = r.recovery;
  if (rec.level == RecoveryLevel.lighter || rec.level == RecoveryLevel.focus) {
    out.add(Insight(
      key: 'recovery:${_d(now)}:${rec.level.name}',
      category: HealthCategory.recovery,
      severity: Severity.advice,
      title: rec.level == RecoveryLevel.focus
          ? 'Уделите внимание восстановлению'
          : 'Рассмотрите более лёгкую тренировку',
      body:
          '${rec.recommendation}\nОтличается от привычного: ${rec.factors.join('; ')}.',
      basis: rec.used,
      period: 'последние дни',
      confidence: rec.hrvUsed
          ? 'средняя (экспериментальная оценка)'
          : 'низкая (экспериментальная оценка, без HRV)',
      createdAt: now,
    ));
  }
  return out;
}
