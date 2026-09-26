import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';

/// help-guide-sheet.tsx, with the "connect" steps adapted to this app
/// (configs connect inside BlackLines; other clients are only for other devices).
Future<void> openHelpGuide(BuildContext context, {String initialSection = 'start'}) => showTgSheet(
      context,
      title: 'راهنمای استفاده',
      description: 'آموزش و سوالات متداول',
      builder: (_) => _HelpGuide(initial: initialSection),
    );

class _HelpGuide extends StatefulWidget {
  const _HelpGuide({required this.initial});

  final String initial;

  @override
  State<_HelpGuide> createState() => _HelpGuideState();
}

class _HelpGuideState extends State<_HelpGuide> {
  late String? openId = widget.initial;

  Widget _accordion(String id, IconData icon, String title, String summary, List<Widget> children) {
    final open = openId == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(10))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => openId = open ? null : id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: C.w(5), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(12))),
                    child: Icon(icon, size: 16, color: C.n200),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t(13, w: 600, c: C.n50)),
                        const Gap(2),
                        Text(summary, style: t(11, c: C.n500, h: 1.6)),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: c)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _step(int n, String title, String body) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.w(5), border: Border.all(color: C.w(15))),
            child: Center(child: Text('$n'.replaceAllMapped(RegExp('[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]), style: t(11, w: 700, c: C.n200))),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t(12, w: 600, c: C.n100)),
                const Gap(2),
                Text(body, style: t(11, c: C.n400, h: 1.6)),
              ],
            ),
          ),
        ],
      );

  Widget _box(String title, String body, {Tone? tone}) {
    final (bg, border, fg) = tone == null ? (C.b(30), C.w(10), C.n100) : toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t(12, w: 600, c: fg)),
          const Gap(4),
          Text(body, style: t(11, c: tone == null ? C.n400 : C.n300, h: 1.6)),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String title, String body) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: C.b(25), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(8))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: C.n300)),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t(12, w: 600, c: C.n100)),
                  const Gap(2),
                  Text(body, style: t(11, c: C.n400, h: 1.6)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _app(String name, String platforms, String hint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: t(13, w: 600, c: C.n50))),
                Tag(platforms),
              ],
            ),
            const Gap(4),
            Text(hint, style: t(11, c: C.n400, h: 1.6)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('راهنما', style: t(14, w: 600, c: C.white)),
        const Gap(2),
        Text('موضوع را باز کنید — بقیه بسته می‌ماند.', style: t(11, c: C.n400)),
        const Gap(10),
        _accordion('start', Icons.auto_awesome, 'شروع سریع', 'از خرید تا وصل شدن در چند قدم', [
          _step(1, 'خرید از فروشگاه', 'در تب فروشگاه یک پلن آماده، پکیج سفارشی یا مصرفی انتخاب کنید و پرداخت را کامل کنید.'),
          _step(2, 'تایید سفارش', 'اگر رسید لازم است تصویر را آپلود کنید. بعد از تایید ادمین، کانفیگ روی داشبورد ظاهر می‌شود.'),
          _step(3, 'اتصال', 'در داشبورد روی دکمه «اتصال» کانفیگ بزنید — همین برنامه وصل می‌شود و وضعیت در تب «اتصال» دیده می‌شود.'),
          _step(4, 'دفعه‌های بعد', 'از تب «اتصال» دکمه روشن/خاموش را بزنید. برای عوض کردن کانفیگ، کارت کانفیگ فعال را بزنید.'),
        ]),
        _accordion('apps', Icons.smartphone_outlined, 'دستگاه‌های دیگر', 'برای لپ‌تاپ، آیفون یا دستگاهی که این برنامه را ندارد', [
          Text(
            'روی همین گوشی نیازی به برنامه دیگری نیست. برای دستگاه‌های دیگر لینک Subscription را کپی کنید و در یکی از این اپ‌ها وارد کنید:',
            style: t(11, c: C.n400, h: 1.6),
          ),
          _app('V2Box', 'iOS / مک', 'برای آیفون و مک مناسب است. از بخش Subscription لینک را اضافه کنید.'),
          _app('Streisand', 'iOS', 'رابط ساده. لینک Sub یا کانفیگ را Import کنید و پروفایل را فعال کنید.'),
          _app('v2rayN / Nekoray', 'ویندوز', 'لینک Sub را در Subscriptions اضافه کنید یا لینک تکی را Import کنید.'),
          _app('V2rayNG', 'اندروید', 'اگر روی گوشی دیگری برنامه BlackLines ندارید: Subscription → + → URL را Paste کنید.'),
        ]),
        _accordion('config', Icons.link_rounded, 'کانفیگ و Subscription', 'تفاوت لینک‌ها و نحوه استفاده', [
          _box(
            'لینک Subscription (پیشنهادی)',
            'یک آدرس ثابت که لیست کانفیگ‌های فعال را می‌دهد. با آپدیت، سرورهای جدید/حذف‌شده خودکار اعمال می‌شوند. در جزئیات کانفیگ دکمه «کپی لینک Subscription» را بزنید.',
            tone: Tone.emerald,
          ),
          _box('بهترین لینک (کم‌پینگ)', 'دکمه «بهترین سرور» همان کانفیگی را کپی می‌کند که الان کم‌ترین پینگ را دارد — برای اتصال سریع مفید است.'),
          _box('لینک‌های تکی', 'هر ردیف یک سرور/پروتکل جداست (Reality، WS و …). اگر Sub کار نکرد، لینک تکی را امتحان کنید.'),
          _box(
            'محدودیت IP و برچسب',
            'تعداد دستگاه مجاز روی هر کانفیگ مشخص است. می‌توانید برای کانفیگ برچسب بگذارید و IPهای متصل را با نام دستگاه (موبایل/لپ‌تاپ) علامت بزنید.',
          ),
        ]),
        _accordion('features', Icons.storefront_outlined, 'امکانات فروشگاه', 'چه چیزهایی در دسترس دارید', [
          _feature(Icons.storefront_outlined, 'پلن آماده و پکیج سفارشی', 'مدت، حجم و تعداد دستگاه را از پلن‌های آماده یا سازنده سفارشی انتخاب کنید.'),
          _feature(
            Icons.account_balance_wallet_outlined,
            'کیف‌پول و تمدید خودکار',
            'موجودی را شارژ کنید، به کیف‌پول کاربر دیگر منتقل کنید، یا برداشت بزنید. روی کانفیگ می‌توانید تمدید خودکار از کیف‌پول را روشن کنید.',
          ),
          _feature(Icons.show_chart_rounded, 'مصرفی ابری و خرید حجم', 'پرداخت به‌اندازه مصرف از کیف‌پول، یا خرید فقط ترافیک بدون محدودیت زمان.'),
          _feature(
            Icons.group_outlined,
            'خرید برای کس دیگری',
            'در فروشگاه «برای کس دیگری» را بزن، اسم مشتری را بنویس و خودت پرداخت کن. بعد از تایید، از میز فروش لینک را کپی و برایش بفرست.',
          ),
          _feature(
            Icons.storefront_outlined,
            'میز فروش',
            'لیست مشتری‌هایت: اسم، چند روز مانده، لینک رفته یا نه. از داشبورد یا پروفایل باز کن؛ کپی، ارسال، تمدید و انتقال یک‌جا است.',
          ),
          _feature(
            Icons.group_outlined,
            'پکیج خانواده',
            'یک پرداخت، چند کانفیگ جدا (والد + فرزند). هر لینک را به همان نفر بفرست. از کانفیگ والد می‌توانی سایت‌های فرزند را محدود کنی.',
          ),
          _feature(Icons.card_giftcard_rounded, 'دعوت دوستان', 'لینک دعوت بگیرید؛ با خرید دوستانتان پورسانت به کیف‌پول شما می‌آید.'),
          _feature(Icons.auto_awesome, 'Pro و تخفیف خرید', 'عضویت Pro و تخفیف‌هایی که ادمین تنظیم کرده هنگام خرید اعمال می‌شوند.'),
          _feature(Icons.shield_outlined, 'هشدار مصرف و انقضا', 'نزدیک پر شدن ترافیک یا انقضا، از طریق تلگرام یادآوری می‌گیرید.'),
        ]),
        _accordion('bot', Icons.chat_bubble_outline_rounded, 'ربات تلگرام', 'ورود و پیام‌های ربات', [
          _step(1, 'ورود به برنامه', 'دکمه «ورود با تلگرام» ربات را باز می‌کند؛ Start را بزنید و به برنامه برگردید.'),
          _step(2, 'پیام‌های ربات', 'یادآوری انقضا، تایید سفارش و پاسخ پشتیبانی در تلگرام هم می‌آید.'),
          _step(3, 'پشتیبانی', 'از تب گفتگو با پشتیبانی پیام بدهید و اشتراک یا فاکتور را پیوست کنید.'),
          _box('نکته', 'وضعیت کانفیگ و مصرف همیشه در داشبورد برنامه به‌روزتر از پیام‌های متنی ربات است.', tone: Tone.amber),
        ]),
        _accordion('faq', Icons.help_outline_rounded, 'سوالات متداول', 'مشکلات رایج و پاسخ سریع', [
          _box(
            'وصل نمی‌شود / تایم‌اوت می‌دهد',
            'در جزئیات کانفیگ «وصل نمیشه؟ تست و تعمیر» را بزنید. اگر همه سرورها قطع بودند کمی صبر کنید یا به پشتیبانی پیام دهید.',
          ),
          _box('تفاوت Subscription با لینک تکی چیست؟', 'Subscription لیست کامل کانفیگ‌های فعال را نگه می‌دارد و با آپدیت عوض می‌شود. لینک تکی فقط همان یک سرور است.'),
          _box('محدودیت دستگاه (IP) چیست؟', 'هر کانفیگ فقط به تعداد مجاز هم‌زمان وصل می‌شود. اگر بیش از حد وصل شوید اتصال جدید قطع یا محدود می‌شود.'),
          _box('چطور تمدید کنم؟', 'در جزئیات کانفیگ بخش تمدید را باز کنید، یا از فروشگاه همان پلن را بخرید. با روشن بودن تمدید خودکار، نزدیک انقضا از کیف‌پول کم می‌شود.'),
          _box('کیف‌پول چه کاربردی دارد؟', 'خرید سریع‌تر، تمدید خودکار، مصرفی ابری، و دریافت پورسانت دعوت. شارژ از بخش کیف‌پول بالای صفحه.'),
          _box('رسید فرستادم ولی هنوز فعال نشده', 'تا تایید ادمین صبر کنید. وضعیت را در اعلان‌ها یا گفتگو ببینید؛ اگر طول کشید در تب گفتگو پیگیری کنید.'),
        ]),
      ],
    );
  }
}
