// Настройки умного помощника: ключ Gemini API, выключатель, проверка ключа.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../shared/widgets.dart';
import 'gemini_service.dart';

const _keysUrl = 'https://aistudio.google.com/api-keys';

/// Подсказка для тех, у кого ИИ ещё не настроен.
Future<void> showAiNotConfigured(BuildContext context) => showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ИИ не настроен'),
        content: const Text(
            'Откройте Настройки → Умный помощник, вставьте свой ключ Gemini API и включите '
            'выключатель. Ключ можно получить бесплатно на aistudio.google.com/api-keys.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))],
      ),
    );

class AiSettingsCard extends ConsumerStatefulWidget {
  const AiSettingsCard({super.key});
  @override
  ConsumerState<AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends ConsumerState<AiSettingsCard> {
  final _key = TextEditingController();
  bool _hasKey = false, _busy = false, _show = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    readAiKey().then((k) {
      if (mounted) setState(() => _hasKey = k != null);
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveAndCheck() async {
    final db = ref.read(dbProvider);
    final k = _key.text.trim();
    if (k.isEmpty) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final model = ((await db.allSettings())[kAiModelKey] ?? '').trim();
      await GeminiClient(k, model: model.isEmpty ? kDefaultAiModel : model).ping();
      await writeAiKey(k);
      await db.setSetting(kAiEnabledKey, '1');
      _key.clear();
      if (mounted) setState(() {
        _hasKey = true;
        _status = 'Ключ принят, помощник включён.';
      });
    } on AiException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeKey() async {
    await writeAiKey(null);
    await ref.read(dbProvider).setSetting(kAiEnabledKey, '0');
    if (mounted) setState(() {
      _hasKey = false;
      _status = 'Ключ удалён с устройства.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).valueOrNull ?? {};
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    final on = s[kAiEnabledKey] == '1';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Умный помощник (Gemini)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          obscureText: !_show,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _saveAndCheck(),
          decoration: InputDecoration(
            labelText: _hasKey ? 'Заменить ключ' : 'Ключ Gemini API',
            suffixIcon: IconButton(
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _saveAndCheck,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Проверить и сохранить'),
        ),
        if (_hasKey)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _removeKey, child: const Text('Удалить ключ')),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: const TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 10),
        Text(
            'Распознаёт еду по фото и советует, чем добрать норму. Нужен ваш бесплатный ключ '
            'Google Gemini API: получите его на aistudio.google.com/api-keys. '
            'Ключ хранится только на этом устройстве.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: _keysUrl));
            if (context.mounted) toast(context, 'Ссылка скопирована, откройте её в браузере');
          },
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Скопировать ссылку на получение ключа'),
        ),
        const SizedBox(height: 4),
        Text(
            'Что уходит в Google: фото еды и данные о нормах и продуктах для советов. На '
            'бесплатном тарифе Google может использовать их для улучшения своих моделей. '
            'Ничего не отправляется, пока помощник выключен.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (_hasKey)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Использовать помощника'),
            value: on,
            onChanged: (v) => db.setSetting(kAiEnabledKey, v ? '1' : '0'),
          ),
      ]),
    );
  }
}
