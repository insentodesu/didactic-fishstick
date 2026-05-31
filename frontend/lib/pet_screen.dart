import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart' as api;
import 'ds.dart';

class PetScreen extends StatefulWidget {
  final VoidCallback? onLesson;
  const PetScreen({super.key, this.onLesson});
  @override
  State<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends State<PetScreen> {
  _PetData? _data;
  bool _loading = true;
  int _petIdx = 0;
  int _envIdx = 0;
  String _customPetName = '';

  static const _petEmojis = ['🐶', '🐱', '🦊', '🐼'];
  static const _envNames = ['Уют', 'Луг', 'Небо'];
  static const _envGrads = [
    [kGoldSoft, kGold],
    [Color(0xFFDBF3E2), kGreen],
    [Color(0xFFE7F0FF), Color(0xFFBBD3FF)],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmojiIdx = prefs.getInt('pet_emoji_idx') ?? 0;
    final savedName = prefs.getString('pet_name') ?? '';
    try {
      final j = await api.getTamagochi();
      if (mounted) setState(() {
        _data = _PetData.fromJson(j);
        _loading = false;
        _petIdx = savedEmojiIdx;
        _customPetName = savedName;
      });
    } catch (_) {
      if (mounted) setState(() {
        _data = _PetData.demo();
        _loading = false;
        _petIdx = savedEmojiIdx;
        _customPetName = savedName;
      });
    }
  }

  Future<void> _savePetPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pet_emoji_idx', _petIdx);
    await prefs.setString('pet_name', _customPetName);
  }

  Future<void> _showEditNameSheet() async {
    final ctrl = TextEditingController(text: _customPetName);
    int tmpIdx = _petIdx;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottom),
                decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Имя питомца', style: dsH3()),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(width: 34, height: 34, decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle), child: const Icon(Icons.close, size: 18, color: kInk1)),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(
                      children: List.generate(_petEmojis.length, (i) {
                        final on = i == tmpIdx;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setSheetState(() => tmpIdx = i),
                            child: Container(
                              margin: EdgeInsets.only(right: i < _petEmojis.length - 1 ? 8 : 0),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: on ? kGoldTint : kSurface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: on ? kGold : kLine, width: 1.5),
                              ),
                              alignment: Alignment.center,
                              child: Text(_petEmojis[i], style: const TextStyle(fontSize: 26)),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctrl,
                      textCapitalization: TextCapitalization.words,
                      style: dsH3(),
                      decoration: InputDecoration(
                        hintText: 'Имя питомца',
                        hintStyle: TextStyle(fontFamily: kFontDisplay, color: kInk3, fontSize: 21),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kLine, width: 2)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kGold, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FpButton.gold(
                      full: true,
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _petIdx = tmpIdx;
                          _customPetName = ctrl.text.trim();
                        });
                        _savePetPrefs();
                      },
                      child: const Text('Сохранить'),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    ctrl.dispose();
  }

  Future<void> _dailyCheckin() async {
    try {
      await api.dailyCheckin();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Бади покормлен! 🦴 +5 сытости'), behavior: SnackBarBehavior.floating));
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
              child: _loading
                  ? FpSkeleton(
                      child: ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                        children: [
                          FpBone(width: 110, height: 11),
                          const SizedBox(height: 16),
                          const FpBone(height: 280, radius: 24),
                          const SizedBox(height: 16),
                          const FpBone(height: 100, radius: 24),
                          const SizedBox(height: 16),
                          const FpBone(height: 140, radius: 24),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: kGold,
                      onRefresh: _load,
                      child: Builder(builder: (ctx) {
                        final wide = isWide(ctx);
                        return ListView(
                          padding: EdgeInsets.fromLTRB(16, 20, 16, wide ? 40 : 100),
                          children: [
                            FpFadeIn(delay: Duration.zero, child: FpOverline('Твой питомец')),
                            const SizedBox(height: 12),
                            if (wide) ...[
                              FpFadeIn(
                                delay: const Duration(milliseconds: 80),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(child: _petCard()),
                                  const SizedBox(width: 16),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                    _chooserCard(),
                                    const SizedBox(height: 16),
                                    _statsCard(),
                                    const SizedBox(height: 16),
                                    _howToCard(),
                                  ])),
                                ]),
                              ),
                            ] else ...[
                              FpFadeIn(delay: const Duration(milliseconds: 80), child: _petCard()),
                              const SizedBox(height: 16),
                              FpFadeIn(delay: const Duration(milliseconds: 160), child: _chooserCard()),
                              const SizedBox(height: 16),
                              FpFadeIn(delay: const Duration(milliseconds: 240), child: _statsCard()),
                              const SizedBox(height: 16),
                              FpFadeIn(delay: const Duration(milliseconds: 300), child: _howToCard()),
                            ],
                          ],
                        );
                      }),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _petCard() {
    final d = _data!;
    final grad = _envGrads[_envIdx];
    final alive = d.isAlive;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kLine),
          boxShadow: shadowMd(),
        ),
        child: Column(
          children: [
            // Pet area with gradient bg
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(0, -0.4),
                  end: Alignment.bottomCenter,
                  colors: grad,
                ),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _dailyCheckin,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        FpPetAvatar(size: 130),
                        if (!alive)
                          const Positioned(
                            right: -4, bottom: -4,
                            child: Text('😴', style: TextStyle(fontSize: 32)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_petEmojis[_petIdx], style: const TextStyle(fontSize: 32)),
                    const SizedBox(width: 8),
                    Text(_customPetName.isNotEmpty ? _customPetName : d.name,
                        style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 26, color: kInk1)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _showEditNameSheet,
                      child: const Icon(Icons.edit_outlined, size: 18, color: kInk3),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    FpChip(child: Row(children: [const Text('⭐', style: TextStyle(fontSize: 13)), const SizedBox(width: 4), Text('Уровень ${d.level}')]), bg: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 8),
                    FpChip(child: Row(children: [const Text('🔥', style: TextStyle(fontSize: 13)), const SizedBox(width: 4), Text('${d.streak} дней')]), bg: Colors.white.withValues(alpha: 0.7)),
                  ]),
                  if (!alive) ...[
                    const SizedBox(height: 10),
                    FpChip(child: const Text('Бади спит — нажми, чтобы разбудить'), bg: kRedBg, color: kRed),
                  ],
                ],
              ),
            ),
            // Needs bars
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  FpNeedsBar(label: '🦴 Сытость', value: d.hunger.toDouble(), color: kGold),
                  const SizedBox(height: 14),
                  FpNeedsBar(label: '❤️ Счастье', value: d.happiness.toDouble(), color: kRed),
                  const SizedBox(height: 14),
                  FpNeedsBar(label: '🧠 Знания', value: d.knowledge.toDouble(), color: kGreen),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kGoldTint, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      _petAdvice(d),
                      style: TextStyle(fontFamily: kFontText, fontSize: 13.5, color: kInk2, height: 1.45),
                    ),
                  ),
                  if (widget.onLesson != null) ...[
                    const SizedBox(height: 14),
                    FpButton.green(
                      full: true,
                      onPressed: widget.onLesson,
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('🎓', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Text('Пройти урок'),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _petAdvice(_PetData d) {
    if (!d.isAlive) return 'Бади задремал. Нажми на него, чтобы разбудить — покорми ежедневным чек-ином.';
    if (d.hunger < 30) return 'Бади проголодался — пройди сегодняшний урок, чтобы покормить его 🦴';
    if (d.streak == 0) return 'Зайди завтра — Бади будет ждать тебя, чтобы начать стрик! 🔥';
    if (d.knowledge < 40) return 'У Бади ещё много знаний впереди. Пройди урок — он вырастет умнее 🧠';
    return 'Бади доволен! Продолжай вести учёт — он растёт вместе с тобой 🌟';
  }

  Widget _chooserCard() {
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FpOverline('Выбери питомца'),
          const SizedBox(height: 12),
          Row(
            children: List.generate(_petEmojis.length, (i) {
              final on = i == _petIdx;
              return Expanded(
                child: GestureDetector(
                  onTap: () { setState(() => _petIdx = i); _savePetPrefs(); },
                  child: Container(
                    margin: EdgeInsets.only(right: i < _petEmojis.length - 1 ? 8 : 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: on ? kGoldTint : kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: on ? kGold : kLine, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(_petEmojis[i], style: const TextStyle(fontSize: 28)),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          FpOverline('Среда обитания'),
          const SizedBox(height: 12),
          Row(
            children: List.generate(_envNames.length, (i) {
              final on = i == _envIdx;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _envIdx = i),
                  child: Container(
                    margin: EdgeInsets.only(right: i < _envNames.length - 1 ? 8 : 0),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: on ? kGold : kLine, width: on ? 2 : 1.5),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _envGrads[i]),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(_envNames[i], style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: kInk2)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _statsCard() {
    final d = _data!;
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FpOverline('Прогресс'),
          const SizedBox(height: 14),
          _statRow('⭐', 'Уровень', d.level.toString()),
          const Divider(color: kLine, height: 1),
          _statRow('⚡', 'Опыт', '${d.experience} XP'),
          const Divider(color: kLine, height: 1),
          _statRow('🔥', 'Стрик', '${d.streak} дней'),
          const Divider(color: kLine, height: 1),
          _statRow('💰', 'Накормлено', fmtRub(d.totalFed)),
        ],
      ),
    );
  }

  Widget _statRow(String emoji, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: dsBody(color: kInk1))),
      Text(value, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 15, color: kInk1)),
    ]),
  );

  Widget _howToCard() => FpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FpOverline('Как растить Бади'),
        const SizedBox(height: 14),
        _howRow('💰', 'Откладывай деньги', 'Кормит питомца и повышает уровень'),
        const Divider(color: kLine, height: 1),
        _howRow('📊', 'Веди учёт трат', 'Поддерживает активность питомца'),
        const Divider(color: kLine, height: 1),
        _howRow('🎓', 'Проходи уроки', 'Добавляет знания +20 за урок'),
        const Divider(color: kLine, height: 1),
        _howRow('📁', 'Загружай выписки', '+15 сытости за каждую выписку'),
      ],
    ),
  );

  Widget _howRow(String emoji, String title, String sub) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: kGoldTint, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1)),
        const SizedBox(height: 2),
        Text(sub, style: dsCaption(color: kInk2).copyWith(fontSize: 12)),
      ])),
    ]),
  );
}

// ============================================================
// Data
// ============================================================

class _PetData {
  final String name;
  final int level, experience, hunger, happiness, knowledge, streak;
  final bool isAlive;
  final double totalFed;

  const _PetData({
    required this.name, required this.level, required this.experience,
    required this.hunger, required this.happiness, required this.knowledge,
    required this.streak, required this.isAlive, required this.totalFed,
  });

  factory _PetData.demo() => const _PetData(
    name: 'Бади', level: 3, experience: 340, hunger: 60, happiness: 80, knowledge: 45, streak: 12, isAlive: true, totalFed: 18900,
  );

  factory _PetData.fromJson(Map<String, dynamic> j) => _PetData(
    name: j['name'] as String? ?? 'Бади',
    level: j['level'] as int? ?? 1,
    experience: j['experience'] as int? ?? 0,
    hunger: j['hunger'] as int? ?? 100,
    happiness: j['happiness'] as int? ?? 100,
    knowledge: (j['health'] as int?) ?? 100,
    streak: j['streak'] as int? ?? 0,
    isAlive: j['is_alive'] as bool? ?? true,
    totalFed: (j['total_fed_amount'] as num?)?.toDouble() ?? 0,
  );
}
