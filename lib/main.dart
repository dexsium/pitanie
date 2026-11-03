import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'database/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  final db = AppDatabase.open();
  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const PitanieApp(),
  ));
}
