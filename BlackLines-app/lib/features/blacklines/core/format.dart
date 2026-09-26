/// Number/date helpers matching miniapp/src/lib/utils.ts.
library;

const _faDigits = '۰۱۲۳۴۵۶۷۸۹';

/// `Math.round(n).toLocaleString("fa-IR")`: Persian digits, `٬` grouping.
String faNum(num n) {
  final v = n.round();
  final neg = v < 0;
  final digits = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('٬');
    buf.write(_faDigits[digits.codeUnitAt(i) - 48]);
  }
  return '${neg ? '-' : ''}$buf';
}

/// Converts ASCII digits inside any string to Persian digits.
String faDigits(String s) => s.replaceAllMapped(RegExp('[0-9]'), (m) => _faDigits[m[0]!.codeUnitAt(0) - 48]);

String priceText(num toman) => '${faNum(toman)} تومان';

/// `800000` -> `800,000` for amount inputs (empty for <= 0).
String formatAmountInput(num n) {
  if (n <= 0) return '';
  final digits = n.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Maps Persian/Arabic-Indic digits to ASCII and drops everything else.
String digitsOnly(String raw) => raw
    .split('')
    .map((c) {
      final fa = _faDigits.indexOf(c);
      if (fa >= 0) return '$fa';
      final ar = '٠١٢٣٤٥٦٧٨٩'.indexOf(c);
      if (ar >= 0) return '$ar';
      return c;
    })
    .join()
    .replaceAll(RegExp(r'\D'), '');

/// Parses a typed amount, accepting ASCII, Persian or Arabic-Indic digits.
int parseAmountInput(String raw) {
  final digits = digitsOnly(raw);
  return digits.isEmpty ? 0 : int.parse(digits);
}

/// App.tsx `remainingDaysHint`.
String remainingDaysHint(String? expiresAt, {bool isPayg = false}) {
  if (expiresAt == null) return 'بدون انقضا';
  final at = DateTime.tryParse(expiresAt);
  if (at == null) return 'بدون انقضا';
  final days = (at.difference(DateTime.now()).inMilliseconds / 86400000).ceil();
  if (days < 0) return 'منقضی';
  if (days == 0) return 'امروز';
  return '${faNum(days)} روز';
}

/// Short Persian relative time ("۵ دقیقه پیش").
String relativeFa(DateTime? at) {
  if (at == null) return '';
  final diff = DateTime.now().difference(at.toLocal());
  if (diff.inSeconds < 60) return 'همین الان';
  if (diff.inMinutes < 60) return '${faNum(diff.inMinutes)} دقیقه پیش';
  if (diff.inHours < 24) return '${faNum(diff.inHours)} ساعت پیش';
  if (diff.inDays < 30) return '${faNum(diff.inDays)} روز پیش';
  return shortDateFa(at);
}

/// Gregorian -> Solar Hijri (Jalali), the calendar `Intl.DateTimeFormat("fa-IR")` uses.
(int, int, int) toJalali(DateTime g) {
  final gy = g.year, gm = g.month, gd = g.day;
  const gDays = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + gd + gDays[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return (jy, jm, jd);
}

const _jalaliMonths = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];

/// `dateStyle: "short"` in fa-IR: ۱۴۰۵/۷/۴.
String shortDateFa(DateTime? at) {
  if (at == null) return '';
  final (y, m, d) = toJalali(at.toLocal());
  return faDigits('$y/$m/$d');
}

/// subscription-detail-sheet.tsx `formatDate`: "۴ مهر ۱۴۰۵، ۱۸:۴۰" (or short form).
String formatDateFa(String? iso, {bool short = false}) {
  if (iso == null) return '—';
  final at = DateTime.tryParse(iso);
  if (at == null) return iso;
  if (short) return shortDateFa(at);
  final (y, m, d) = toJalali(at.toLocal());
  return '${faDigits('$d')} ${_jalaliMonths[m - 1]} ${faDigits('$y')}، ${timeFa(at)}';
}

String timeFa(DateTime? at) {
  if (at == null) return '';
  final l = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return faDigits('${two(l.hour)}:${two(l.minute)}');
}

String bytesLabel(num bytes) {
  if (bytes < 1024) return '${faNum(bytes)} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${faDigits(v.toStringAsFixed(v >= 100 ? 0 : 1))} ${units[i]}';
}

/// chat-panel.tsx `formatChatTime` (fa-IR day + short month + time): "۴ مهر، ۱۸:۴۰".
String chatTimeFa(String? iso) {
  final at = iso == null ? null : DateTime.tryParse(iso);
  if (at == null) return '';
  final (_, m, d) = toJalali(at.toLocal());
  return '${faDigits('$d')} ${_jalaliMonths[m - 1]}، ${timeFa(at)}';
}
