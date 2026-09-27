import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';

/// admin-panel.tsx `Chip` (h-5 rounded-md text-[10px]).
class AdminChip extends StatelessWidget {
  const AdminChip(this.text, {super.key, this.tone});

  final String text;

  /// amber / orange / null (muted).
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = tone;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c == null ? C.w(5) : C.a(c, 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c == null ? C.w(10) : C.a(c, 0.3)),
      ),
      child: Center(widthFactor: 1, child: Text(text, style: t(10, c: c == null ? C.n300 : C.a(c, 0.95)))),
    );
  }
}

/// Small labeled digits-only field used across admin settings.
class NumField extends StatelessWidget {
  const NumField({super.key, required this.label, required this.controller, this.hint, this.enabled = true});

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t(10, c: C.n500)),
        const Gap(4),
        SizedBox(
          height: 36,
          child: TextField(
            controller: controller,
            enabled: enabled,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: t(14, c: C.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: t(13, c: C.n600),
              filled: true,
              fillColor: C.b(40),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(25))),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(8))),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-column grid of [NumField]s.
class NumGrid extends StatelessWidget {
  const NumGrid({super.key, required this.fields, this.columns = 2, this.enabled = true});

  final List<(String label, TextEditingController c)> fields;
  final int columns;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += columns) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const Gap(8),
                Expanded(
                  child: i + j < fields.length
                      ? NumField(label: fields[i + j].$1, controller: fields[i + j].$2, enabled: enabled)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class CheckLine extends StatelessWidget {
  const CheckLine({super.key, required this.value, required this.onChanged, required this.label, this.small = false});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(width: 24, height: 24, child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false))),
              const Gap(6),
              Expanded(child: Text(label, style: t(small ? 11 : 13, c: small ? C.n400 : C.n300))),
            ],
          ),
        ),
      );
}

/// admin-panel.tsx `AccordionSection`.
class AdminAccordion extends StatelessWidget {
  const AdminAccordion({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: C.b(45), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(12))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: C.w(8), borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 16, color: C.n300),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t(14, w: 600)),
                        const Gap(2),
                        Text(summary, style: t(11, c: C.n400, h: 1.6)),
                      ],
                    ),
                  ),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: C.w(8)))),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Small bordered text area (broadcast, trial targets, domains).
class AreaField extends StatelessWidget {
  const AreaField({super.key, required this.controller, this.hint, this.ltr = false, this.lines = 3, this.onChanged});

  final TextEditingController controller;
  final String? hint;
  final bool ltr;
  final int lines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines + 3,
        onChanged: onChanged,
        textDirection: ltr ? TextDirection.ltr : null,
        style: t(ltr ? 12 : 14, c: C.white, mono: ltr, h: 1.6),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintTextDirection: ltr ? TextDirection.ltr : null,
          hintStyle: t(12, c: C.n600),
          filled: true,
          fillColor: C.b(40),
          contentPadding: const EdgeInsets.all(12),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.w(15))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.w(25))),
        ),
      );
}

int? parseIntOrNull(String s) => int.tryParse(s.trim());
