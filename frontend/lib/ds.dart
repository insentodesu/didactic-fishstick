import 'dart:math' as math;
import 'package:flutter/material.dart';

// ============================================================
// FinPet Design System — tokens
// ============================================================

// Brand
const kGold = Color(0xFFFDB201);
const kGoldDeep = Color(0xFFF4AE01);
const kGoldSoft = Color(0xFFFEE998);
const kGoldTint = Color(0xFFFFF6D6);

// Forest
const kForest900 = Color(0xFF143324);
const kForest700 = Color(0xFF1E5631);
const kForest500 = Color(0xFF2E7D46);

// Traffic light
const kGreen = Color(0xFF03A250);
const kGreenBright = Color(0xFF66D751);
const kGreenBg = Color(0xFFE4F6EC);
const kGreenRing = Color(0xFFB7E6CB);
const kYellow = Color(0xFFF4AE01);
const kYellowBg = Color(0xFFFEF3D6);
const kYellowRing = Color(0xFFF7DC9B);
const kRed = Color(0xFFF9554C);
const kRedBg = Color(0xFFFDE6E4);
const kRedRing = Color(0xFFF6BDB8);

// Neutrals
const kCream = Color(0xFFFFFCF2);
const kSurface = Color(0xFFFFFFFF);
const kSurface2 = Color(0xFFFBF8EF);
const kLine = Color(0xFFECE6D6);
const kLineStrong = Color(0xFFDED6C0);
const kInk1 = Color(0xFF143324);
const kInk2 = Color(0xFF4F5A4F);
const kInk3 = Color(0xFF87917F);
const kInkOnGold = Color(0xFF2A2300);

// ============================================================
// Typography
// ============================================================

const kFontDisplay = 'YandexSansDisplay';
const kFontText = 'YandexSansText';

TextStyle dsDisplay({double size = 56, Color color = kInk1, FontWeight weight = FontWeight.w700}) =>
    TextStyle(fontFamily: kFontDisplay, fontWeight: weight, fontSize: size, color: color, letterSpacing: -0.02 * size);

TextStyle dsH1({Color color = kInk1}) =>
    const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 40, color: kInk1, letterSpacing: -0.6);

TextStyle dsH2({Color color = kInk1}) =>
    TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 28, color: color, letterSpacing: -0.28);

TextStyle dsH3({Color color = kInk1}) =>
    TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 21, color: color);

TextStyle dsBody({Color color = kInk1}) =>
    TextStyle(fontFamily: kFontText, fontWeight: FontWeight.w400, fontSize: 16, color: color, height: 1.55);

TextStyle dsSmall({Color color = kInk2}) =>
    TextStyle(fontFamily: kFontText, fontWeight: FontWeight.w400, fontSize: 14, color: color, height: 1.5);

TextStyle dsCaption({Color color = kInk3}) =>
    TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w400, fontSize: 12, color: color, letterSpacing: 0.12);

TextStyle dsOverline({Color color = kInk3}) =>
    TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: color, letterSpacing: 1.44);

TextStyle dsMetric({double size = 44, Color color = kInk1}) =>
    TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: size, color: color, letterSpacing: -size * 0.02, fontFeatures: [const FontFeature.tabularFigures()]);

// ============================================================
// Zone helpers
// ============================================================

enum FinZone { green, yellow, red }

FinZone zoneFor(double pdn) {
  if (pdn < 30) return FinZone.green;
  if (pdn <= 50) return FinZone.yellow;
  return FinZone.red;
}

class ZoneColors {
  final Color c, bg, ring;
  final String label, hint;
  const ZoneColors({required this.c, required this.bg, required this.ring, required this.label, required this.hint});
}

ZoneColors zoneColors(FinZone z) {
  switch (z) {
    case FinZone.green:
      return const ZoneColors(c: kGreen, bg: kGreenBg, ring: kGreenRing, label: 'ЗЕЛЁНАЯ ЗОНА', hint: 'Нагрузка в норме');
    case FinZone.yellow:
      return const ZoneColors(c: kYellow, bg: kYellowBg, ring: kYellowRing, label: 'ЖЁЛТАЯ ЗОНА', hint: 'Зона внимания');
    case FinZone.red:
      return const ZoneColors(c: kRed, bg: kRedBg, ring: kRedRing, label: 'КРАСНАЯ ЗОНА', hint: 'Нужен план сейчас');
  }
}

String zoneTitle(FinZone z) {
  switch (z) {
    case FinZone.green: return 'Ты в зелёной зоне';
    case FinZone.yellow: return 'Ты в жёлтой зоне';
    case FinZone.red: return 'Ты в красной зоне';
  }
}

// ============================================================
// Shadows
// ============================================================

List<BoxShadow> shadowMd() => [
  BoxShadow(color: const Color(0xFF143324).withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)),
  BoxShadow(color: const Color(0xFF143324).withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
];

List<BoxShadow> shadowGold() => [
  BoxShadow(color: kGold.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8)),
];

// ============================================================
// Base Widgets
// ============================================================

class FpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final BoxDecoration? decoration;
  final VoidCallback? onTap;

  const FpCard({super.key, required this.child, this.padding, this.decoration, this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = decoration ??
        BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kLine, width: 1),
          boxShadow: shadowMd(),
        );
    final p = padding ?? const EdgeInsets.all(18);
    Widget w = Container(decoration: d, padding: p, child: child);
    if (onTap != null) w = GestureDetector(onTap: onTap, child: w);
    return w;
  }
}

class FpOverline extends StatelessWidget {
  final String text;
  final Color color;
  const FpOverline(this.text, {super.key, this.color = kInk3});

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: dsOverline(color: color));
  }
}

class FpChip extends StatelessWidget {
  final Widget child;
  final Color bg;
  final Color color;
  final Color? border;

  const FpChip({super.key, required this.child, this.bg = kGoldTint, this.color = kInk1, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border!) : null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: color),
        child: child,
      ),
    );
  }
}

class FpButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final _BtnVariant variant;
  final bool full;
  final double height;

  const FpButton({super.key, required this.child, this.onPressed, this.variant = _BtnVariant.primary, this.full = false, this.height = 52});
  const FpButton.gold({super.key, required this.child, this.onPressed, this.full = false, this.height = 52})
      : variant = _BtnVariant.primary;
  const FpButton.green({super.key, required this.child, this.onPressed, this.full = false, this.height = 52})
      : variant = _BtnVariant.green;
  const FpButton.secondary({super.key, required this.child, this.onPressed, this.full = false, this.height = 48})
      : variant = _BtnVariant.secondary;
  const FpButton.ghost({super.key, required this.child, this.onPressed, this.full = false, this.height = 44})
      : variant = _BtnVariant.ghost;

  @override
  State<FpButton> createState() => _FpButtonState();
}

enum _BtnVariant { primary, green, secondary, ghost }

class _FpButtonState extends State<FpButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    List<BoxShadow> shadows = [];
    Border? border;

    switch (widget.variant) {
      case _BtnVariant.primary:
        bg = kGold;
        fg = kInkOnGold;
        shadows = shadowGold();
        break;
      case _BtnVariant.green:
        bg = kGreen;
        fg = Colors.white;
        shadows = [BoxShadow(color: kGreen.withValues(alpha: 0.28), blurRadius: 20, offset: const Offset(0, 8))];
        break;
      case _BtnVariant.secondary:
        bg = kSurface;
        fg = kInk1;
        border = Border.all(color: kLineStrong, width: 1.5);
        break;
      case _BtnVariant.ghost:
        bg = Colors.transparent;
        fg = kForest700;
        break;
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: widget.full ? double.infinity : null,
          height: widget.height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: border,
            boxShadow: widget.onPressed == null ? [] : shadows,
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 16, color: fg),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Ring progress widget (SVG-style circular arc)
// ============================================================

class FpRing extends StatelessWidget {
  final double value; // 0–100
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? child;
  final Duration animDuration;

  const FpRing({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 13,
    this.color = kGreen,
    this.track = kGreenBg,
    this.child,
    this.animDuration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: animDuration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, v, innerChild) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(value: v.clamp(0, 100), color: color, track: track, stroke: stroke),
            ),
            if (innerChild != null) innerChild,
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color, track;
  final double stroke;
  const _RingPainter({required this.value, required this.color, required this.track, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;

    final trackPaint = Paint()
      ..color = track
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    final arcPaint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * (value / 100);
    canvas.drawArc(rect, start, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

// ============================================================
// Pet avatar
// ============================================================

class FpPetAvatar extends StatelessWidget {
  final double size;
  const FpPetAvatar({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(0, -0.24),
          colors: [kGoldSoft, kGold],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/images/finpet-mascot.png', fit: BoxFit.cover),
    );
  }
}

// ============================================================
// Needs bar
// ============================================================

class FpNeedsBar extends StatelessWidget {
  final String label;
  final double value; // 0–100
  final Color color;
  final Duration animDuration;

  const FpNeedsBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.animDuration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: dsCaption(color: kInk2).copyWith(fontSize: 13, fontFamily: kFontDisplay, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kLine),
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value / 100).clamp(0.0, 1.0)),
              duration: animDuration,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text('${value.round()}%', style: dsCaption(color: kInk3).copyWith(fontSize: 12)),
        ),
      ],
    );
  }
}

// ============================================================
// Money format
// ============================================================

String fmtRub(double n) {
  final neg = n < 0;
  final abs = n.abs();
  final str = abs.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return '${neg ? '−' : ''}$str ₽';
}

String fmtRubSigned(double n) {
  return '${n >= 0 ? '+' : ''}${fmtRub(n)}';
}

// ============================================================
// FpFadeIn — fade + slide-up on mount, supports stagger delay
// ============================================================

class FpFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  const FpFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offsetY = 18,
  });

  @override
  State<FpFadeIn> createState() => _FpFadeInState();
}

class _FpFadeInState extends State<FpFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 300),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ============================================================
// _SkeletonBone — for loading skeletons
// ============================================================

class FpSkeletonBone extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final Color color;

  const FpSkeletonBone({
    super.key,
    this.width,
    required this.height,
    this.radius = 10,
    this.color = kLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ============================================================
// FpSkeleton — shimmer loading placeholder
// ============================================================

class FpSkeleton extends StatefulWidget {
  final Widget child;
  const FpSkeleton({super.key, required this.child});

  @override
  State<FpSkeleton> createState() => _FpSkeletonState();
}

class _FpSkeletonState extends State<FpSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = (_ctrl.value * 2 - 1).abs();
        final shade = Color.lerp(const Color(0xFFECE6D6), const Color(0xFFF8F4EA), t)!;
        return _FpSkeletonTheme(color: shade, child: widget.child);
      },
    );
  }
}

class _FpSkeletonTheme extends InheritedWidget {
  final Color color;
  const _FpSkeletonTheme({required this.color, required super.child});

  static Color of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_FpSkeletonTheme>()?.color ?? kLine;
  }

  @override
  bool updateShouldNotify(_FpSkeletonTheme old) => old.color != color;
}

class FpBone extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const FpBone({super.key, this.width, required this.height, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _FpSkeletonTheme.of(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
