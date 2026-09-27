import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';

void haptic([String kind = 'light']) {
  switch (kind) {
    case 'medium':
      HapticFeedback.mediumImpact();
    case 'heavy' || 'error':
      HapticFeedback.heavyImpact();
    default:
      HapticFeedback.lightImpact();
  }
}

// ---------------------------------------------------------------------------
// Background (gradient-field.tsx + .feral-* in index.css)
// ---------------------------------------------------------------------------

class GradientField extends StatefulWidget {
  const GradientField({super.key, required this.child});

  final Widget child;

  @override
  State<GradientField> createState() => _GradientFieldState();
}

class _GradientFieldState extends State<GradientField> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 26))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _blob(double size, Color color, double opacity) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)], stops: const [0, 0.68]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return ColoredBox(
      color: C.background,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = Curves.easeInOut.transform(_c.value);
              return Stack(
                children: [
                  Positioned(
                    top: -0.16 * h + v * 0.08 * w,
                    left: -0.22 * w + v * 0.1 * w,
                    child: _blob(0.68 * w * (1 + 0.06 * v), C.light ? const Color(0xFFC9B7A2) : const Color(0xFFD4D4D4), C.light ? 0.42 : 0.5),
                  ),
                  Positioned(
                    top: 0.22 * h + v * 0.06 * w,
                    right: -0.38 * w + v * 0.08 * w,
                    child: _blob(0.8 * w, C.light ? const Color(0xFF9A9186) : const Color(0xFF737373), C.light ? 0.38 : 0.5),
                  ),
                  Positioned(
                    bottom: -0.18 * h + v * 0.1 * w,
                    left: 0.12 * w + v * 0.06 * w,
                    child: _blob(0.55 * w, C.n50, 0.22),
                  ),
                ],
              );
            },
          ),
          // .feral-veil
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: C.light
                        ? const [Color(0x47F3F1EC), Color(0x8CF3F1EC), Color(0xE6F3F1EC)]
                        : const [Color(0x40050505), Color(0x80050505), Color(0xEB050505)],
                    stops: [0, 0.42, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// App.tsx `Panel`: rounded-2xl border-white/12 bg-black/45 p-4.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.radius = 16,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? C.b(45),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? C.w(12)),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: box),
    );
  }
}

/// Small rounded box used for stats (`rounded-xl border-white/12 bg-white/5 p-3`).
class StatBox extends StatelessWidget {
  const StatBox({super.key, required this.label, required this.value, this.valueColor, this.center = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.w(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.w(12)),
      ),
      child: Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(label, style: t(11, c: C.n400)),
          const SizedBox(height: 4),
          Text(value, style: t(14, w: 600, c: valueColor)),
        ],
      ),
    );
  }
}

/// Collapsible section (`ShopPurchaseOptions`, dashboard usage summary, archive).
class Collapsible extends StatefulWidget {
  const Collapsible({
    super.key,
    required this.title,
    required this.child,
    this.hint,
    this.icon,
    this.badge,
    this.initiallyOpen = false,
    this.trailingText,
  });

  final String title;
  final String? hint;
  final IconData? icon;
  final String? badge;
  final bool initiallyOpen;
  final Widget child;
  final (String, String)? trailingText;

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: C.b(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.w(10)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (widget.icon != null) ...[Icon(widget.icon, size: 14, color: C.n400), const SizedBox(width: 6)],
                            Flexible(child: Text(widget.title, style: t(12, w: 600, c: C.n200))),
                            if (widget.badge != null) ...[
                              const SizedBox(width: 6),
                              Tag(widget.badge!, tone: Tone.emerald),
                            ],
                          ],
                        ),
                        if (!open && widget.hint != null) ...[
                          const SizedBox(height: 2),
                          Text(widget.hint!, style: t(10, c: C.n500)),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailingText != null)
                    Text(open ? widget.trailingText!.$2 : widget.trailingText!.$1, style: t(10, c: C.n500))
                  else
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: C.n500),
                    ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: C.w(8)))),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons & chips
// ---------------------------------------------------------------------------

enum BtnVariant { primary, outline, ghost }

/// tg-button.tsx: h-11 rounded-xl text-sm font-semibold.
class TgButton extends StatelessWidget {
  const TgButton({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.variant = BtnVariant.primary,
    this.icon,
    this.busy = false,
    this.height = 44,
    this.fontSize = 14,
    this.expand = true,
    this.color,
    this.foreground,
  });

  final String? label;
  final Widget? child;
  final VoidCallback? onPressed;
  final BtnVariant variant;
  final IconData? icon;
  final bool busy;
  final double height;
  final double fontSize;
  final bool expand;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final fg = foreground ??
        switch (variant) {
          BtnVariant.primary => C.primaryFg,
          BtnVariant.outline => C.foreground,
          BtnVariant.ghost => C.mutedFg,
        };
    final bg = color ??
        switch (variant) {
          BtnVariant.primary => C.primary,
          _ => Colors.transparent,
        };
    final content = busy
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : child ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: fontSize + 2, color: fg), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label ?? '',
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: t(fontSize, w: 600, c: fg),
                  ),
                ),
              ],
            );
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: variant == BtnVariant.outline ? BorderSide(color: C.border) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // widthFactor 1: a non-expanding button hugs its label instead of filling the row.
              child: Center(
                widthFactor: expand ? null : 1,
                child: DefaultTextStyle.merge(style: t(fontSize, w: 600, c: fg), child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// App.tsx `Chip`: h-6 rounded-lg border-white/12 bg-white/5 text-[11px].
class MiniChip extends StatelessWidget {
  const MiniChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: C.w(5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: C.w(12)),
      ),
      child: Center(widthFactor: 1, child: Text(text, style: t(11, c: C.n300))),
    );
  }
}

enum Tone { neutral, emerald, red, amber, sky, teal, rose, violet, white }

(Color bg, Color border, Color fg) toneColors(Tone tone) => switch (tone) {
      Tone.emerald => (C.a(C.emerald500, 0.15), C.a(C.emerald400, 0.4), C.emerald200),
      Tone.red => (C.a(C.red500, 0.15), C.a(C.red500, 0.35), C.red200),
      Tone.amber => (C.a(C.amber500, 0.15), C.a(C.amber400, 0.4), C.amber200),
      Tone.sky => (C.a(C.sky500, 0.1), C.a(C.sky500, 0.25), C.sky100),
      Tone.teal => (C.a(C.teal500, 0.1), C.a(C.teal500, 0.25), C.teal100),
      Tone.rose => (C.a(C.rose500, 0.12), C.a(C.rose500, 0.3), C.rose200),
      Tone.violet => (C.a(C.violet500, 0.12), C.a(C.violet500, 0.3), C.violet300),
      Tone.white => (C.w(10), C.w(20), C.foreground),
      Tone.neutral => (C.w(10), C.w(20), C.n300),
    };

/// Small status pill (`rounded-md border px-1.5 py-0.5 text-[10px]`).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = Tone.neutral, this.size = 10});

  final String text;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
      child: Text(text, style: t(size, w: 500, c: fg)),
    );
  }
}

/// Tinted callout box (`rounded-lg border border-sky-500/20 bg-sky-500/10 px-2.5 py-1.5 text-[11px]`).
class Callout extends StatelessWidget {
  const Callout(this.text, {super.key, this.tone = Tone.sky, this.icon});

  final String text;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = toneColors(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
          Expanded(child: Text(text, style: t(11, c: fg, h: 1.6))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tabs / segmented controls
// ---------------------------------------------------------------------------

/// Grid segmented control (shop sections, payg mode): selected = white pill.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.value, required this.onChanged});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.b(35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.w(10)),
      ),
      child: Row(
        children: [
          for (final (id, label) in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () {
                    haptic();
                    onChanged(id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // Theme primary: white on dark, near-black on light.
                      color: id == value ? C.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(label, style: t(11, w: 600, c: id == value ? C.primaryFg : C.n400)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// filter-bar.tsx: horizontally scrolling pills.
class FilterBar<T> extends StatelessWidget {
  const FilterBar({super.key, required this.items, required this.value, required this.onChanged});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (id, label) = items[i];
          final active = id == value;
          return GestureDetector(
            onTap: () {
              haptic();
              onChanged(id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? C.primary : C.b(40),
                borderRadius: BorderRadius.circular(999),
                border: active ? null : Border.all(color: C.w(15)),
              ),
              child: Text(label, style: t(12, w: 600, c: active ? C.primaryFg : C.n400)),
            ),
          );
        },
      ),
    );
  }
}

/// Underline tabs (wallet sheet, detail sheet).
class UnderlineTabs<T> extends StatelessWidget {
  const UnderlineTabs({super.key, required this.items, required this.value, required this.onChanged});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.w(10)))),
      child: Row(
        children: [
          for (final (id, label) in items)
            Expanded(
              child: InkWell(
                onTap: () {
                  haptic();
                  onChanged(id);
                },
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(label, style: t(13, w: id == value ? 600 : 500, c: id == value ? C.foreground : C.n500)),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 2,
                      color: id == value ? C.foreground : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form
// ---------------------------------------------------------------------------

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: t(13, w: 500, c: C.n300));
}

/// ui/input.tsx with the app's `h-11 rounded-xl border-white/15 bg-black/40` overrides.
class BLInput extends StatelessWidget {
  const BLInput({
    super.key,
    this.controller,
    this.hint,
    this.ltr = false,
    this.numeric = false,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.prefixIcon,
    this.onSubmitted,
    this.keyboardType,
    this.maxLength,
    this.autofocus = false,
    this.textAlign,
  });

  final TextEditingController? controller;
  final String? hint;
  final bool ltr;
  final bool numeric;
  final ValueChanged<String>? onChanged;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final IconData? prefixIcon;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool autofocus;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c));
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      textAlign: textAlign ?? TextAlign.start,
      textDirection: ltr ? TextDirection.ltr : null,
      keyboardType: keyboardType ?? (numeric ? TextInputType.number : null),
      style: t(15),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: hint,
        hintTextDirection: ltr ? TextDirection.ltr : null,
        hintStyle: t(14, c: C.n500),
        filled: true,
        fillColor: C.b(40),
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18, color: C.n500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: border(C.w(15)),
        enabledBorder: border(C.w(15)),
        focusedBorder: border(C.w(25)),
        disabledBorder: border(C.w(8)),
      ),
    );
  }
}

/// Amount field with `formatAmountInput`/`parseAmountInput` and a "تومان" suffix.
class AmountInput extends StatefulWidget {
  const AmountInput({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<AmountInput> createState() => _AmountInputState();
}

class _AmountInputState extends State<AmountInput> {
  late final _c = TextEditingController(text: formatAmountInput(widget.value));

  @override
  void didUpdateWidget(AmountInput old) {
    super.didUpdateWidget(old);
    final formatted = formatAmountInput(widget.value);
    if (_c.text != formatted) {
      _c.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: BLInput(
            controller: _c,
            ltr: true,
            numeric: true,
            hint: '100,000',
            onChanged: (v) => widget.onChanged(parseAmountInput(v)),
          ),
        ),
        const SizedBox(width: 8),
        Text('تومان', style: t(14, w: 500, c: C.n300)),
      ],
    );
  }
}

/// Numeric stepper used by the package builders (− value +).
class NumStepper extends StatelessWidget {
  const NumStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.format,
    this.enabled = true,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String Function(int)? format;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, int next) => SizedBox(
          width: 36,
          height: 36,
          child: Material(
            color: C.w(8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: C.w(12))),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: !enabled || next < min || next > max
                  ? null
                  : () {
                      haptic();
                      onChanged(next);
                    },
              child: Icon(icon, size: 18, color: next < min || next > max ? C.n600 : C.foreground),
            ),
          ),
        );
    return Row(
      children: [
        Expanded(child: Text(label, style: t(13, w: 500, c: C.n300))),
        btn(Icons.remove_rounded, value - step),
        SizedBox(
          width: 88,
          child: Text(format?.call(value) ?? faNum(value), textAlign: TextAlign.center, style: t(14, w: 700)),
        ),
        btn(Icons.add_rounded, value + step),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Text blocks
// ---------------------------------------------------------------------------

/// shop-purchase-options.tsx `ShopSectionIntro`.
class SectionIntro extends StatelessWidget {
  const SectionIntro({super.key, required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t(14, w: 600, c: C.white)),
          const SizedBox(height: 2),
          Text(description, style: t(11, c: C.n400, h: 1.6)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t(15, w: 600)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: t(12, c: C.n400, h: 1.6)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Key/value row used in detail sheets.
class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.ltr = false, this.valueColor});

  final String k;
  final String v;
  final bool ltr;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: t(12, c: C.n400)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.end,
              textDirection: ltr ? TextDirection.ltr : null,
              style: t(12, w: 500, c: valueColor ?? C.n100),
            ),
          ),
        ],
      ),
    );
  }
}

class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

// ---------------------------------------------------------------------------
// Loaders
// ---------------------------------------------------------------------------

/// Stand-in for `thinking-orbs`: a softly pulsing, rotating grayscale orb.
class OrbLoader extends StatefulWidget {
  const OrbLoader({super.key, this.size = 64});

  final double size;

  @override
  State<OrbLoader> createState() => _OrbLoaderState();
}

class _OrbLoaderState extends State<OrbLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pulse = 0.88 + 0.12 * math.sin(_c.value * 2 * math.pi);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Transform.rotate(
            angle: _c.value * 2 * math.pi,
            child: Transform.scale(
              scale: pulse,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [C.w(90), C.w(15), C.w(55), C.w(8), C.w(90)],
                  ),
                  boxShadow: [BoxShadow(color: C.w(18), blurRadius: widget.size / 3)],
                ),
                child: Padding(
                  padding: EdgeInsets.all(widget.size * 0.14),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [Color(0xFF1A1A1A), Color(0xFF050505)]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OrbLoaderPanel extends StatelessWidget {
  const OrbLoaderPanel({super.key, this.message = 'در حال بارگذاری…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const OrbLoader(),
          const SizedBox(height: 12),
          Text(message, style: t(13, c: C.n400)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.actions = const []});

  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Column(
        children: [
          const Opacity(opacity: 0.65, child: OrbLoader()),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: t(14, c: C.n400)),
          for (final a in actions) ...[const SizedBox(height: 12), a],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet (tg-sheet.tsx)
// ---------------------------------------------------------------------------

Future<T?> showTgSheet<T>(
  BuildContext context, {
  required String title,
  String? description,
  required Widget Function(BuildContext context) builder,
  bool scrollable = true,
  Widget? titleWidget,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: C.scrim,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Container(
              decoration: BoxDecoration(
                color: C.sheet,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  top: BorderSide(color: C.w(15)),
                  left: BorderSide(color: C.w(15)),
                  right: BorderSide(color: C.w(15)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.w(10)))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleWidget ?? Text(title, style: t(14, w: 600, c: C.white)),
                              if (description != null && description.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t(11, c: C.n400),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Material(
                            color: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: C.w(15)),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.of(ctx).pop(),
                              child: Icon(Icons.close_rounded, size: 16, color: C.n300),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: scrollable
                        ? SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(ctx).bottom),
                            child: builder(ctx),
                          )
                        : Padding(
                            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(ctx).bottom),
                            child: builder(ctx),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Confirm dialog in sheet form (replaces `window.confirm` in the mini app).
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'تأیید',
  bool destructive = false,
}) async {
  final ok = await showTgSheet<bool>(
    context,
    title: title,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: t(13, c: C.n300, h: 1.7)),
        const Gap(16),
        TgButton(
          label: confirm,
          color: destructive ? C.a(C.red500, 0.85) : null,
          foreground: destructive ? Colors.white : null,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        const Gap(8),
        TgButton(label: 'انصراف', variant: BtnVariant.outline, onPressed: () => Navigator.of(ctx).pop(false)),
      ],
    ),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------------------
// Toasts (tg-toast.tsx) — top-centered, max 2, 2.6s
// ---------------------------------------------------------------------------

enum ToastStatus { success, error, info }

class _Toast {
  _Toast(this.id, this.title, this.status);
  final int id;
  final String title;
  final ToastStatus status;
}

class Toasts extends ChangeNotifier {
  Toasts._();
  static final instance = Toasts._();

  final List<_Toast> _items = [];
  var _seq = 0;

  void push(String title, [ToastStatus status = ToastStatus.info]) {
    final toast = _Toast(_seq++, title, status);
    _items.add(toast);
    while (_items.length > 2) {
      _items.removeAt(0);
    }
    if (status == ToastStatus.success) HapticFeedback.lightImpact();
    if (status == ToastStatus.error) HapticFeedback.heavyImpact();
    notifyListeners();
    Timer(const Duration(milliseconds: 2600), () => dismiss(toast.id));
  }

  void dismiss(int id) {
    _items.removeWhere((x) => x.id == id);
    notifyListeners();
  }
}

void notify(String title, [ToastStatus status = ToastStatus.info]) => Toasts.instance.push(title, status);

class ToastHost extends StatelessWidget {
  const ToastHost({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Toasts.instance,
      builder: (context, _) {
        final items = Toasts.instance._items;
        return IgnorePointer(
          ignoring: items.isEmpty,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => Toasts.instance.dismiss(item.id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 384),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: item.status == ToastStatus.error ? C.n900 : C.primary,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: item.status == ToastStatus.error ? C.n800 : C.border),
                              boxShadow: [BoxShadow(color: C.b(35), blurRadius: 16, offset: const Offset(0, 6))],
                            ),
                            child: Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: t(12, w: 500, c: item.status == ToastStatus.error ? C.n50 : C.primaryFg),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header pieces
// ---------------------------------------------------------------------------

/// motion/notification-bell.tsx (static version): bell + orange count badge.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.count, required this.onTap, this.size = 36});

  final int count;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: C.b(60),
            shape: CircleBorder(side: BorderSide(color: C.w(15))),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.expand(child: Icon(Icons.notifications_none_rounded, size: size * 0.5, color: C.n300)),
            ),
          ),
          if (count > 0)
            Positioned(
              top: -3,
              left: -3,
              child: Container(
                constraints: BoxConstraints(minWidth: size * 0.46, minHeight: size * 0.46),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.orange500,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: C.background, width: 1.5),
                ),
                child: Text(count > 99 ? '۹۹+' : faNum(count), style: t(9.5, w: 700, c: C.white)),
              ),
            ),
        ],
      ),
    );
  }
}

/// pro-header-entry.tsx.
class ProHeaderEntry extends StatelessWidget {
  const ProHeaderEntry({super.key, required this.isPro, required this.onTap});

  final bool isPro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lightChip = C.light && !isPro;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: isPro ? 12 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: lightChip ? const Color(0xFFD4D4D4) : const Color(0x33FFFFFF)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: lightChip ? const [Colors.white, Colors.white] : [isPro ? C.n800 : C.n900, Colors.black],
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded, size: 15, color: lightChip ? const Color(0xFFEAB308) : const Color(0xFFFCD34D)),
              const SizedBox(width: 4),
              Text(isPro ? 'PRO' : 'Pro', style: t(11, w: 800, c: lightChip ? const Color(0xFF171717) : Colors.white)),
              if (isPro) ...[const SizedBox(width: 4), const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFD4D4D4))],
            ],
          ),
        ),
      ),
    );
  }
}

/// "در حال پردازش…" floating pill shown while `busy`.
class BusyPill extends StatelessWidget {
  const BusyPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: C.b(80),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: C.w(15)),
        boxShadow: [BoxShadow(color: C.b(40), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6)),
          const SizedBox(width: 8),
          Text('در حال پردازش…', style: t(11, c: C.n300)),
        ],
      ),
    );
  }
}

/// Status → (label, tone) used across dashboard and admin (App.tsx `statusMeta`).
(String, Tone) statusMeta(String? status) => switch (status) {
      'online' => ('آنلاین', Tone.emerald),
      'expired' => ('منقضی', Tone.red),
      'disabled' => ('غیرفعال', Tone.amber),
      _ => ('آفلاین', Tone.neutral),
    };

/// Withdrawal/order status tone.
Tone statusTone(String? status) => switch (status) {
      'paid' || 'approved' || 'completed' => Tone.emerald,
      'rejected' || 'cancelled' || 'canceled' => Tone.red,
      _ => Tone.amber,
    };

/// Rounded-full choice pill (`h-8 rounded-full border px-3 text-xs`), sized to its label.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.active, required this.onTap, this.tone});

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Optional accent (e.g. rose for "settle debt").
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final accent = tone;
    return GestureDetector(
      onTap: () {
        haptic();
        onTap();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: accent != null ? C.a(accent, active ? 0.2 : 0.1) : (active ? C.primary : C.b(40)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent != null ? C.a(accent, active ? 0.5 : 0.3) : (active ? C.primary : C.w(15))),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: t(12, w: 500, c: accent != null ? C.rose200 : (active ? C.primaryFg : C.n300))),
        ),
      ),
    );
  }
}
