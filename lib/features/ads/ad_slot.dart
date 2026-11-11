import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ad_provider.dart';
import 'ads_models.dart';

/// Рекламное место. Занимает место на экране только когда не превышены лимиты и сеть вернула
/// объявление; иначе не занимает места вообще. Подпись «Реклама» появляется вместе с
/// объявлением и не перекрывает содержимое экрана.
class AdSlot extends ConsumerStatefulWidget {
  final AdPlacement placement;
  const AdSlot(this.placement, {super.key});

  @override
  ConsumerState<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends ConsumerState<AdSlot> {
  Widget? _ad;
  bool _loaded = false; // объявление реально загружено (подпись видна)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = ref.read(adProviderProvider);
    // Без подключённой сети ничего не проверяется и не запрашивается.
    if (!provider.available) return;
    final service = ref.read(adsServiceProvider);
    final p = widget.placement;
    // Заглушка не подчиняется лимитам и не учитывается в счётчиках.
    if (!provider.isPlaceholder && await service.decide(p) != AdDecision.allowed) return;
    Widget? ad;
    try {
      ad = await provider.buildAd(p,
          events: AdEvents(
            onLoaded: () {
              service.recordImpression(p);
              if (mounted) setState(() => _loaded = true);
            },
            onFailed: () {
              service.recordError(p);
              if (mounted) {
                setState(() {
                  _ad = null;
                  _loaded = false;
                });
              }
            },
          ));
    } catch (_) {
      ad = null;
    }
    if (ad == null) {
      // Размещение без блока в сети (provider вернул null) ошибкой не считается.
      if (!provider.isPlaceholder && provider.reportsOwnEvents == false) {
        await service.recordError(p);
      }
      return;
    }
    if (provider.reportsOwnEvents) {
      // Объявление грузится само: оно должно быть в дереве виджетов, чтобы загрузиться.
      if (mounted) setState(() => _ad = ad);
      return;
    }
    if (!provider.isPlaceholder) await service.recordImpression(p);
    if (mounted) {
      setState(() {
        _ad = ad;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: _loaded ? 8 : 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_loaded && !ref.read(adProviderProvider).providesLabel(widget.placement)) ...[
          Text('Реклама', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
        ],
        ad,
      ]),
    );
  }
}
