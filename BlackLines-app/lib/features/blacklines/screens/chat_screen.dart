import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/receipt_viewer.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _pollEvery = Duration(milliseconds: 2500);
const _maxAttachments = 3;

String _threadTitle(J t) => t.text('full_name') ?? (t.text('username') != null ? '@${t.s('username')}' : faNum(t.i('telegram_id')));

/// Merges by id and keeps order (chat-panel.tsx `mergeMessages`).
List<J> _merge(List<J> prev, List<J> incoming) {
  if (incoming.isEmpty) return prev;
  final byId = <int, J>{for (final m in prev.where((m) => m.i('id') > 0)) m.i('id'): m};
  for (final m in incoming) {
    byId[m.i('id')] = m;
  }
  return byId.values.toList()..sort((a, b) => a.i('id').compareTo(b.i('id')));
}

/// Composer attachment draft → API input (`draftToInput`).
Map<String, dynamic> _toInput(J d) => switch (d.s('type')) {
      'link' => {'type': 'link', 'subscription_id': d.i('subscription_id'), 'link_index': d.i('link_index')},
      'order' => {'type': 'order', 'order_id': d.i('order_id')},
      _ => {'type': 'subscription', 'subscription_id': d.i('subscription_id')},
    };

/// chat-panel.tsx `ChatPanel`.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  J? activeThread;

  @override
  void initState() {
    super.initState();
    final c = ref.read(blControllerProvider);
    final open = c.openChatThreadUserId;
    if (c.isAdmin && open != null) {
      c.consumeOpenThread();
      _openThreadFor(open);
    }
  }

  Future<void> _openThreadFor(int userId) async {
    final api = ref.read(blControllerProvider).api;
    try {
      final data = await api.adminChatThreads();
      var thread = data.objs('threads').where((t) => t.i('user_id') == userId).firstOrNull;
      if (thread == null) {
        final u = await api.adminUserDetail(userId);
        thread = J({
          'user_id': u.i('id'),
          'telegram_id': u.i('telegram_id'),
          'username': u['username'],
          'full_name': u['full_name'],
          'last_message': '',
          'last_message_at': null,
          'last_sender': null,
          'unread_count': u.i('chat_unread'),
        });
      }
      if (mounted) setState(() => activeThread = thread);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(blControllerProvider.select((c) => c.isAdmin));
    if (!isAdmin) return const _Conversation();
    if (activeThread case final th?) {
      return _Conversation(
        key: ValueKey(th.i('user_id')),
        thread: th,
        onBack: () => setState(() => activeThread = null),
        onThreadMeta: (patch) => setState(() => activeThread = th.merge(patch)),
      );
    }
    return _AdminThreads(onSelect: (t) => setState(() => activeThread = t));
  }
}

// ---------------------------------------------------------------------------
// Admin thread list
// ---------------------------------------------------------------------------

class _AdminThreads extends ConsumerStatefulWidget {
  const _AdminThreads({required this.onSelect});

  final ValueChanged<J> onSelect;

  @override
  ConsumerState<_AdminThreads> createState() => _AdminThreadsState();
}

class _AdminThreadsState extends ConsumerState<_AdminThreads> {
  List<J> threads = const [];
  bool loading = true;
  bool onDuty = false;
  int dutyCount = 0;
  bool dutyBusy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_pollEvery * 2, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final c = ref.read(blControllerProvider);
    try {
      final d = await c.api.adminChatThreads();
      if (!mounted) return;
      setState(() {
        threads = d.objs('threads');
        onDuty = d.b('on_duty');
        dutyCount = d.i('duty_count');
      });
      c.setChatUnread(d.i('unread_total'));
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.w(10)))),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: C.n500),
              const Gap(6),
              Expanded(child: Text('گفتگو با کاربران', style: t(12, w: 600, c: C.n300))),
              GestureDetector(
                onTap: dutyBusy
                    ? null
                    : () async {
                        setState(() => dutyBusy = true);
                        try {
                          final r = await ref.read(blControllerProvider).api.adminSetDuty(!onDuty);
                          haptic();
                          setState(() {
                            onDuty = r.b('on_duty');
                            dutyCount = r.i('duty_count');
                          });
                        } catch (_) {
                        } finally {
                          if (mounted) setState(() => dutyBusy = false);
                        }
                      },
                child: Tag(onDuty ? 'آن‌دیوتی · ${faNum(dutyCount)}' : 'شروع شیفت', tone: onDuty ? Tone.emerald : Tone.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: OrbLoaderPanel(message: 'در حال بارگذاری گفتگوها…'))
              : threads.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 40, color: C.n600),
                          const Gap(8),
                          Text('هنوز گفتگویی ثبت نشده', style: t(14, c: C.n400)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.builder(
                        itemCount: threads.length,
                        itemBuilder: (_, i) {
                          final th = threads[i];
                          final title = _threadTitle(th);
                          return InkWell(
                            onTap: () {
                              haptic();
                              widget.onSelect(th);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.w(8)))),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: C.w(10),
                                    child: Text(title.isEmpty ? '?' : title[0].toUpperCase(), style: t(12, w: 700)),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: t(14, w: 600))),
                                            if (th.text('last_message_at') != null)
                                              Text(chatTimeFa(th.text('last_message_at')), style: t(10, c: C.n500)),
                                          ],
                                        ),
                                        const Gap(2),
                                        Text(
                                          '${th.s('last_sender') == 'admin' ? 'شما: ' : ''}${th.text('last_message') ?? '—'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t(12, c: C.n400),
                                        ),
                                        const Gap(2),
                                        Text(
                                          th.text('assigned_name') != null ? 'مسئول: ${th.s('assigned_name')}' : 'بدون مسئول شیفت',
                                          style: t(10, c: th.text('assigned_name') != null ? C.a(C.sky300, 0.8) : C.n600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (th.i('unread_count') > 0) ...[
                                    const Gap(8),
                                    Container(
                                      width: 20,
                                      height: 20,
                                      margin: const EdgeInsets.only(top: 4),
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                      child: Center(
                                        child: Text(faNum(th.i('unread_count').clamp(0, 9)), style: t(10, w: 700, c: Colors.black)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation (UserChat / AdminThreadChat)
// ---------------------------------------------------------------------------

class _Conversation extends ConsumerStatefulWidget {
  const _Conversation({super.key, this.thread, this.onBack, this.onThreadMeta});

  /// Null for the user's own support chat.
  final J? thread;
  final VoidCallback? onBack;
  final ValueChanged<Map<String, dynamic>>? onThreadMeta;

  @override
  ConsumerState<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends ConsumerState<_Conversation> {
  List<J> messages = const [];
  Map<int, J> liveOrders = const {};
  bool loading = true;
  bool busy = false;
  bool claimBusy = false;
  String? error;
  int _lastId = 0;
  bool _inflight = false;
  Timer? _timer;
  final _scroll = ScrollController();

  bool get isAdmin => widget.thread != null;
  int get userId => widget.thread?.i('user_id') ?? 0;
  BLController get c => ref.read(blControllerProvider);
  String get _cacheKey => isAdmin ? 'chat_$userId' : 'chat_me';

  void _saveCache() {
    final keep = messages.where((m) => m.i('id') > 0).toList();
    c.writeCache(_cacheKey, [for (final m in keep.skip(keep.length > 200 ? keep.length - 200 : 0)) m.raw]);
  }

  @override
  void initState() {
    super.initState();
    if (isAdmin) {
      c.api.adminChatMarkRead(userId).catchError((_) => const J({}));
    } else {
      c.api.chatMarkRead().catchError((_) => const J({}));
    }
    // Show the last saved conversation instantly; the poll below refreshes it.
    final cached = J.list(c.readCache(_cacheKey));
    if (cached.isNotEmpty) {
      messages = cached;
      _lastId = cached.last.i('id');
      loading = false;
      _toBottom(smooth: false);
    }
    _poll(initial: true);
    _refreshOrders();
    _timer = Timer.periodic(_pollEvery, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool get _nearBottom => !_scroll.hasClients || _scroll.position.pixels < 96;

  void _toBottom({bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      // The list is reversed, so "bottom" is offset 0.
      smooth ? _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : _scroll.jumpTo(0);
    });
  }

  Future<void> _refreshOrders() async {
    try {
      final d = isAdmin ? await c.api.adminThreadOrders(userId) : await c.api.chatOrders();
      if (mounted) setState(() => liveOrders = {for (final o in d.objs('items')) o.i('id'): o});
    } catch (_) {}
  }

  Future<void> _poll({bool initial = false}) async {
    if (_inflight) return;
    _inflight = true;
    try {
      final after = initial ? 0 : _lastId;
      final d = isAdmin ? await c.api.adminChatMessages(userId, afterId: after) : await c.api.chatMessages(afterId: after);
      c.setChatUnread(isAdmin ? d.i('unread_total') : d.i('unread_count'));
      final incoming = d.objs('messages');
      if (initial) {
        messages = incoming;
        if (incoming.isNotEmpty) _lastId = incoming.last.i('id');
        error = null;
        _toBottom(smooth: false);
        _saveCache();
      } else if (d.i('latest_id') > _lastId) {
        final wasNear = _nearBottom;
        messages = _merge(messages, incoming);
        if (messages.isNotEmpty) _lastId = messages.last.i('id');
        if (wasNear) _toBottom();
        _saveCache();
      }
      if (mounted) setState(() {});
    } catch (e) {
      // Cached messages stay on screen; only an empty thread shows the error.
      if (initial && mounted && messages.isEmpty) setState(() => error = persianError(e));
    } finally {
      _inflight = false;
      if (initial && mounted) setState(() => loading = false);
    }
  }

  Future<void> _send(String body, List<J> drafts) async {
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final optimistic = J({
      'id': tempId,
      'user_id': userId,
      'sender': isAdmin ? 'admin' : 'user',
      'body': body,
      'attachments': [for (final d in drafts) d.raw],
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'read_at': null,
      'pending': true,
    });
    setState(() {
      messages = [...messages, optimistic];
      busy = true;
    });
    _toBottom();
    try {
      final inputs = drafts.map(_toInput).toList();
      final res = isAdmin ? await c.api.adminChatSend(userId, body, inputs) : await c.api.chatSend(body, inputs);
      final msg = res.obj('message');
      setState(() {
        messages = _merge(messages.where((m) => m.i('id') != tempId).toList(), [msg]);
        _lastId = msg.i('id');
      });
      _saveCache();
    } catch (e) {
      setState(() => messages = messages.where((m) => m.i('id') != tempId).toList());
      notify(persianError(e), ToastStatus.error);
      rethrow;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleClaim() async {
    final th = widget.thread!;
    setState(() => claimBusy = true);
    try {
      if (th.intOrNull('assigned_admin_id') != null) {
        await c.api.adminReleaseChat(userId);
        widget.onThreadMeta?.call({'assigned_admin_id': null, 'assigned_name': null});
      } else {
        final r = await c.api.adminClaimChat(userId);
        widget.onThreadMeta?.call({'assigned_admin_id': r.i('assigned_admin_id'), 'assigned_name': r['assigned_name']});
      }
      haptic();
    } catch (_) {
    } finally {
      if (mounted) setState(() => claimBusy = false);
    }
  }

  void _openAttachment(J att) {
    haptic();
    showAttachmentDetail(
      context,
      att: att,
      isAdmin: isAdmin,
      threadUserId: isAdmin ? userId : null,
      onOrderAction: () {
        _refreshOrders();
        c.handleOrderAction();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.thread;
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: th == null ? 16 : 12, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.w(10)))),
          child: th == null
              ? Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 16, color: C.n400),
                    const Gap(8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('گفتگو با پشتیبانی', style: t(14, w: 600)),
                          Text('پیام خود را بنویسید — تیم ما پاسخ می‌دهد', style: t(11, c: C.n400)),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        haptic();
                        widget.onBack?.call();
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_threadTitle(th), overflow: TextOverflow.ellipsis, style: t(14, w: 600)),
                          Text(
                            '${faNum(th.i('telegram_id'))}${th.text('assigned_name') != null ? ' · مسئول: ${th.s('assigned_name')}' : ''}',
                            style: t(11, c: C.n400),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: claimBusy ? null : _toggleClaim,
                      child: Opacity(
                        opacity: claimBusy ? 0.5 : 1,
                        child: Tag(th.intOrNull('assigned_admin_id') != null ? 'آزاد کردن' : 'قبول شیفت', tone: Tone.white, size: 11),
                      ),
                    ),
                  ],
                ),
        ),
        Expanded(
          child: loading
              ? const Center(child: OrbLoaderPanel(message: 'در حال بارگذاری گفتگو…'))
              : error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!, textAlign: TextAlign.center, style: t(14, c: C.n400)),
                            const Gap(12),
                            TgButton(label: 'تلاش دوباره', expand: false, onPressed: () => _poll(initial: true)),
                          ],
                        ),
                      ),
                    )
                  : messages.isEmpty
                      ? Center(
                          child: Container(
                            margin: const EdgeInsets.all(24),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(15))),
                            child: Text(
                              isAdmin ? 'هنوز پیامی در این گفتگو نیست.' : 'هنوز پیامی ندارید. سوال یا درخواست خود را اینجا بنویسید.',
                              textAlign: TextAlign.center,
                              style: t(14, c: C.n400),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[messages.length - 1 - i];
                            final mine = m.s('sender') == (isAdmin ? 'admin' : 'user');
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _Bubble(msg: m, mine: mine, liveOrders: liveOrders, onOpen: _openAttachment),
                            );
                          },
                        ),
        ),
        if (!loading)
          _Composer(
            busy: busy,
            placeholder: isAdmin ? 'پاسخ به کاربر…' : 'پیام خود را بنویسید…',
            onSend: _send,
            loadSubs: () async => isAdmin
                ? (await c.api.adminThreadSubscriptions(userId)).objs('items')
                : (await c.api.subscriptions()).objs('items'),
            loadOrders: () async =>
                isAdmin ? (await c.api.adminThreadOrders(userId)).objs('items') : (await c.api.chatOrders()).objs('items'),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.mine, required this.liveOrders, required this.onOpen});

  final J msg;
  final bool mine;
  final Map<int, J> liveOrders;
  final ValueChanged<J> onOpen;

  @override
  Widget build(BuildContext context) {
    final body = msg.text('body');
    final atts = msg.objs('attachments');
    final pending = msg.b('pending');
    return Align(
      // RTL: "mine" sits at the visual left (end), like the mini app's self-end.
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: pending ? 0.7 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: mine ? Colors.white : C.w(10),
                  border: mine ? null : Border.all(color: C.w(12)),
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: const Radius.circular(16),
                    topEnd: const Radius.circular(16),
                    bottomStart: Radius.circular(mine ? 16 : 6),
                    bottomEnd: Radius.circular(mine ? 6 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (body != null) SelectableText(body, style: t(14, c: mine ? Colors.black : C.n100, h: 1.6)),
                    for (var i = 0; i < atts.length; i++) ...[
                      if (body != null || i > 0) const Gap(6),
                      _AttachmentCard(att: _withLive(atts[i]), mine: mine, onOpen: onOpen),
                    ],
                  ],
                ),
              ),
            ),
            const Gap(2),
            Text(pending ? 'در حال ارسال…' : chatTimeFa(msg.text('created_at')), style: t(10, c: C.n500)),
          ],
        ),
      ),
    );
  }

  /// `mergeLiveOrder`: show the order's current status, not the one at send time.
  J _withLive(J att) {
    if (att.s('type') != 'order') return att;
    final live = liveOrders[att.i('order_id')];
    if (live == null) return att;
    return att.merge({
      for (final k in const ['status', 'status_label', 'has_receipt', 'amount_label', 'wallet_used', 'wallet_used_label']) k: live[k],
    });
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.att, required this.mine, required this.onOpen});

  final J att;
  final bool mine;
  final ValueChanged<J> onOpen;

  @override
  Widget build(BuildContext context) {
    final type = att.s('type');
    final isLink = type == 'link';
    final isOrder = type == 'order';
    final title = isOrder
        ? '${att.text('kind_label') ?? 'فاکتور'} · ${att.text('plan_title') ?? '—'}'
        : (att.text('label') ?? att.text('plan_title') ?? att.s('email'));
    final fg = mine ? C.b(80) : C.n200;
    final sub = mine ? C.b(55) : C.n400;
    return GestureDetector(
      onTap: () => onOpen(att),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? C.b(5) : C.b(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: mine ? C.b(15) : C.w(15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: mine ? C.b(8) : C.w(10), borderRadius: BorderRadius.circular(8)),
              child: Icon(
                isOrder ? Icons.receipt_long_outlined : (isLink ? Icons.link_rounded : Icons.inventory_2_outlined),
                size: 14,
                color: fg,
              ),
            ),
            const Gap(8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isLink ? 'لینک · $title' : title, style: t(11, w: 600, c: fg)),
                  if (isOrder) Text('فاکتور #${att.intOrNull('order_id') != null ? faNum(att.i('order_id')) : '—'}', style: t(10, c: sub)),
                  if (att.text('email') != null)
                    Text(att.s('email'), textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis, style: t(10, c: sub, mono: true)),
                  if (isLink && (att.text('link_preview') ?? att.text('link')) != null)
                    Text(
                      att.text('link_preview') ?? att.s('link'),
                      textDirection: TextDirection.ltr,
                      overflow: TextOverflow.ellipsis,
                      style: t(10, c: sub, mono: true),
                    ),
                  if (isOrder && att.text('amount_label') != null) Text(att.s('amount_label'), style: t(12, c: fg)),
                  if (!isOrder && att.text('plan_title') != null) Text(att.s('plan_title'), style: t(10, c: sub)),
                  if (isOrder)
                    Text(
                      [
                        att.text('status_label'),
                        if (att.b('has_receipt')) 'رسید دارد',
                        if (att.i('wallet_used') > 0 && att.text('wallet_used_label') != null) 'کیف‌پول ${att.s('wallet_used_label')}',
                      ].whereType<String>().join(' · '),
                      style: t(10, c: sub),
                    ),
                  const Gap(2),
                  Text('برای جزئیات بزنید', style: t(10, c: mine ? C.b(35) : C.n600)),
                ],
              ),
            ),
            if (isLink && att.text('link') != null)
              GestureDetector(
                onTap: () => copyText(att.s('link')),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: mine ? C.b(10) : C.w(10), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.copy_rounded, size: 14, color: fg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// chat-composer-bar.tsx
// ---------------------------------------------------------------------------

class _Composer extends StatefulWidget {
  const _Composer({
    required this.busy,
    required this.placeholder,
    required this.onSend,
    required this.loadSubs,
    required this.loadOrders,
  });

  final bool busy;
  final String placeholder;
  final Future<void> Function(String body, List<J> drafts) onSend;
  final Future<List<J>> Function() loadSubs;
  final Future<List<J>> Function() loadOrders;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  List<J> drafts = [];

  bool get canSend => (_text.text.trim().isNotEmpty || drafts.isNotEmpty) && !widget.busy;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!canSend) return;
    haptic();
    final body = _text.text.trim();
    final toSend = drafts;
    _text.clear();
    setState(() => drafts = []);
    try {
      await widget.onSend(body, toSend);
    } catch (_) {
      // Restore so nothing typed is lost.
      if (_text.text.isEmpty) _text.text = body;
      setState(() => drafts = toSend);
    } finally {
      _focus.requestFocus();
    }
  }

  Future<void> _attach() async {
    if (drafts.length >= _maxAttachments) {
      notify('حداکثر ${faNum(_maxAttachments)} پیوست');
      return;
    }
    haptic();
    final picked = await showTgSheet<J>(
      context,
      title: 'افزودن پیوست',
      builder: (_) => _AttachPicker(loadSubs: widget.loadSubs, loadOrders: widget.loadOrders),
    );
    if (picked != null) setState(() => drafts = [...drafts, picked]);
  }

  String _chipLabel(J d) => switch (d.s('type')) {
        'order' => 'فاکتور #${faNum(d.i('order_id'))}',
        'link' => 'لینک · ${d.text('label') ?? d.s('plan_title')}',
        _ => d.text('label') ?? d.s('plan_title'),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.b(80), border: Border(top: BorderSide(color: C.w(10)))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (drafts.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < drafts.length; i++)
                  Container(
                    padding: const EdgeInsetsDirectional.only(start: 10, end: 4, top: 4, bottom: 4),
                    decoration: BoxDecoration(color: C.w(8), borderRadius: BorderRadius.circular(999), border: Border.all(color: C.w(12))),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(_chipLabel(drafts[i]), overflow: TextOverflow.ellipsis, style: t(11, c: C.n200)),
                        ),
                        const Gap(4),
                        GestureDetector(
                          onTap: () => setState(() => drafts = [...drafts]..removeAt(i)),
                          child: Icon(Icons.close_rounded, size: 14, color: C.n400),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Gap(8),
          ],
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: C.w(6), borderRadius: BorderRadius.circular(20), border: Border.all(color: C.w(12))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _RoundBtn(icon: Icons.add_rounded, onTap: _attach, filled: false),
                const Gap(6),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    style: t(14, c: C.white, h: 1.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.placeholder,
                      hintStyle: t(14, c: C.n500),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                const Gap(6),
                _RoundBtn(icon: Icons.arrow_upward_rounded, onTap: canSend ? _send : null, filled: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, required this.filled});

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: filled ? Colors.white : C.w(10), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: filled ? Colors.black : C.n200),
          ),
        ),
      );
}

/// Composer attach menu: root → subs / links / orders.
class _AttachPicker extends ConsumerStatefulWidget {
  const _AttachPicker({required this.loadSubs, required this.loadOrders});

  final Future<List<J>> Function() loadSubs;
  final Future<List<J>> Function() loadOrders;

  @override
  ConsumerState<_AttachPicker> createState() => _AttachPickerState();
}

class _AttachPickerState extends ConsumerState<_AttachPicker> {
  String step = 'root';
  bool linkMode = false;
  bool loading = false;
  List<J> subs = const [];
  List<J> orders = const [];
  J? linksSub;
  List<String> links = const [];

  Future<void> _loadCatalog() async {
    if (subs.isNotEmpty || orders.isNotEmpty) return;
    setState(() => loading = true);
    try {
      final r = await Future.wait([widget.loadSubs(), widget.loadOrders()]);
      if (mounted) {
        setState(() {
          subs = r[0];
          orders = r[1];
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openLinks(J sub) async {
    setState(() {
      linksSub = sub;
      step = 'links';
      loading = true;
    });
    try {
      final d = await ref.read(blControllerProvider).api.links(sub.i('id'));
      if (mounted) setState(() => links = d.strs('links'));
    } catch (_) {
      if (mounted) setState(() => links = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _subTitle(J s) => s.text('label') ?? s.text('plan_title') ?? s.s('email');

  Widget _row(IconData icon, String name, String desc, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          haptic();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: C.w(8), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: C.n200),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, overflow: TextOverflow.ellipsis, style: t(13, w: 500)),
                    Text(desc, overflow: TextOverflow.ellipsis, style: t(11, c: C.n500)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pop = Navigator.of(context).pop;
    final title = switch (step) {
      'subs' => linkMode ? 'انتخاب اشتراک برای لینک' : 'انتخاب اشتراک',
      'orders' => 'انتخاب فاکتور',
      'links' => 'لینک‌های ${linksSub == null ? '' : _subTitle(linksSub!)}',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (step != 'root') ...[
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => step = step == 'links' ? 'subs' : 'root'),
                child: Text('→ بازگشت', style: t(11, c: C.n400)),
              ),
              const Spacer(),
              Text(title!, style: t(11, w: 500, c: C.n300)),
            ],
          ),
          const Gap(8),
        ],
        if (loading)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('در حال بارگذاری…', textAlign: TextAlign.center, style: t(12, c: C.n500)))
        else if (step == 'root') ...[
          _row(Icons.inventory_2_outlined, 'اشتراک', 'ارسال اطلاعات یک اشتراک', () {
            setState(() {
              step = 'subs';
              linkMode = false;
            });
            _loadCatalog();
          }),
          _row(Icons.link_rounded, 'لینک VPN', 'یک لینک vless از اشتراک', () {
            setState(() {
              step = 'subs';
              linkMode = true;
            });
            _loadCatalog();
          }),
          _row(Icons.receipt_long_outlined, 'فاکتور', 'خرید VPN یا شارژ کیف‌پول', () {
            setState(() => step = 'orders');
            _loadCatalog();
          }),
        ] else if (step == 'subs')
          if (subs.isEmpty)
            Text('اشتراکی نیست.', textAlign: TextAlign.center, style: t(12, c: C.n500))
          else
            for (final s in subs)
              _row(
                Icons.vpn_key_outlined,
                _subTitle(s),
                '${s.s('plan_title')}${s.text('traffic_label') != null ? ' · ${s.s('traffic_label')}' : ''}',
                () => linkMode
                    ? _openLinks(s)
                    : pop(J({
                        'type': 'subscription',
                        'subscription_id': s.i('id'),
                        'email': s['email'],
                        'label': s['label'],
                        'plan_title': s['plan_title'],
                      })),
              )
        else if (step == 'orders')
          if (orders.isEmpty)
            Text('فاکتوری نیست.', textAlign: TextAlign.center, style: t(12, c: C.n500))
          else
            for (final o in orders)
              _row(
                Icons.receipt_long_outlined,
                '${o.s('kind_label')} · ${o.s('plan_title')}',
                '${o.s('amount_label')} · ${o.s('status_label')}${o.b('has_receipt') ? ' · رسید' : ''}',
                () => pop(J({
                  'type': 'order',
                  'order_id': o.i('id'),
                  for (final k in const ['plan_title', 'kind', 'kind_label', 'amount_label', 'status_label', 'has_receipt']) k: o[k],
                })),
              )
        else
          for (var i = 0; i < links.length; i++)
            _row(
              Icons.link_rounded,
              'لینک ${faNum(i + 1)}',
              links[i].length > 48 ? '${links[i].substring(0, 47)}…' : links[i],
              () => pop(J({
                'type': 'link',
                'subscription_id': linksSub!.i('id'),
                'link_index': i,
                'email': linksSub!['email'],
                'label': linksSub!['label'],
                'plan_title': linksSub!['plan_title'],
                'link_preview': links[i].length > 52 ? '${links[i].substring(0, 51)}…' : links[i],
              })),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// chat-attachment-detail-sheet.tsx
// ---------------------------------------------------------------------------

Future<void> showAttachmentDetail(
  BuildContext context, {
  required J att,
  required bool isAdmin,
  int? threadUserId,
  VoidCallback? onOrderAction,
}) {
  final type = att.s('type');
  return showTgSheet(
    context,
    title: type == 'order' ? 'جزئیات فاکتور' : (type == 'link' ? 'جزئیات لینک VPN' : 'جزئیات اشتراک'),
    description: type == 'order' ? '#${faNum(att.i('order_id'))}' : att.text('email'),
    builder: (_) => _AttachmentDetail(att: att, isAdmin: isAdmin, threadUserId: threadUserId, onOrderAction: onOrderAction),
  );
}

class _AttachmentDetail extends ConsumerStatefulWidget {
  const _AttachmentDetail({required this.att, required this.isAdmin, this.threadUserId, this.onOrderAction});

  final J att;
  final bool isAdmin;
  final int? threadUserId;
  final VoidCallback? onOrderAction;

  @override
  ConsumerState<_AttachmentDetail> createState() => _AttachmentDetailState();
}

class _AttachmentDetailState extends ConsumerState<_AttachmentDetail> {
  bool loading = true;
  bool orderBusy = false;
  bool uploading = false;
  List<String> links = const [];
  J? dashItem;
  J? orderFresh;
  final _label = TextEditingController();

  J get att => widget.att;
  String get type => att.s('type');
  int? get subId => type == 'order' ? null : att.intOrNull('subscription_id');
  int? get orderId => type == 'order' ? att.intOrNull('order_id') : null;
  BLController get c => ref.read(blControllerProvider);

  @override
  void initState() {
    super.initState();
    _label.text = att.text('label') ?? '';
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      if (subId != null) {
        links = (await c.api.links(subId!)).strs('links');
        if (!widget.isAdmin) {
          try {
            dashItem = (await c.api.dashboard()).objs('items').where((i) => i.i('id') == subId).firstOrNull;
          } catch (_) {}
        }
      }
      if (orderId != null) {
        final items = widget.isAdmin
            ? (widget.threadUserId != null ? (await c.api.adminThreadOrders(widget.threadUserId!)).objs('items') : const <J>[])
            : (await c.api.chatOrders()).objs('items');
        orderFresh = items.where((o) => o.i('id') == orderId).firstOrNull;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _orderAct(Future<J> Function() fn, String ok, {bool close = false}) async {
    setState(() => orderBusy = true);
    try {
      await fn();
      haptic();
      notify(ok, ToastStatus.success);
      widget.onOrderAction?.call();
      if (close && mounted) {
        Navigator.of(context).pop();
      } else {
        await _load();
      }
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      if (mounted) setState(() => orderBusy = false);
    }
  }

  Future<void> _uploadAdminReceipt() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    final f = res?.files.singleOrNull;
    if (f?.path == null) return;
    setState(() => uploading = true);
    try {
      await c.api.adminUploadReceipt(orderId!, f!.path!, f.name);
      haptic();
      notify('رسید ثبت شد', ToastStatus.success);
      widget.onOrderAction?.call();
      await _load();
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Widget _rows(List<(String, String, bool)> rows) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: C.w(8)))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rows[i].$1, style: t(11, c: C.n500)),
                    const Gap(12),
                    Expanded(
                      child: Text(
                        rows[i].$2,
                        textAlign: TextAlign.end,
                        textDirection: rows[i].$3 ? TextDirection.ltr : null,
                        style: t(rows[i].$3 ? 11 : 12, c: C.n100, mono: rows[i].$3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _btn(String label, VoidCallback? onTap, {IconData? icon, bool danger = false, bool primary = false}) => TgButton(
        label: label,
        icon: icon,
        variant: primary ? BtnVariant.primary : BtnVariant.outline,
        foreground: danger ? C.red300 : null,
        height: 40,
        fontSize: 12,
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: C.w(5), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: Text('در حال بارگذاری جزئیات…', textAlign: TextAlign.center, style: t(12, c: C.n400)),
      );
    }
    final gap = const Gap(8);
    if (type == 'subscription') {
      final d = dashItem;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rows([
            ('نام / برچسب', att.text('label') ?? '—', false),
            ('پلن', att.text('plan_title') ?? '—', false),
            ('ایمیل', att.text('email') ?? '—', true),
            if (d != null) ...[
              ('مصرف', '${faNum(d.d('usage_percent').round())}٪ · ${d.s('used_label')} / ${d.s('total_label')}', false),
              ('اتصال', d.b('online') ? 'آنلاین' : 'آفلاین', false),
              ('انقضا', d.text('expires_at') != null ? formatDateFa(d.text('expires_at'), short: true) : '—', false),
            ],
          ]),
          const Gap(16),
          if (!widget.isAdmin) ...[
            Text('برچسب اشتراک', style: t(11, c: C.n400)),
            gap,
            BLInput(controller: _label, hint: 'مثلاً لپ‌تاپ', maxLength: 64),
            gap,
            _btn('ذخیره برچسب', () async {
              await c.renameConfig(subId!, _label.text.trim());
              await _load();
            }),
            const Gap(16),
          ],
          if (links.isNotEmpty) ...[
            Text('لینک‌های VPN', style: t(11, w: 500, c: C.n300)),
            gap,
            for (final l in links) ...[_LinkRow(link: l), const Gap(6)],
            const Gap(8),
          ],
          if (att.text('email') != null) ...[_btn('کپی ایمیل', () => copyText(att.s('email'))), gap],
          if (!widget.isAdmin) ...[
            _btn('باز کردن در داشبورد', () {
              Navigator.of(context).pop();
              c.switchTab(BLTab.subs);
            }, icon: Icons.open_in_new_rounded),
            gap,
          ],
          _btn('بروزرسانی', _load, icon: Icons.refresh_rounded),
        ],
      );
    }
    if (type == 'link') {
      final idx = att.intOrNull('link_index');
      final resolved = att.text('link') ?? (idx != null && idx < links.length ? links[idx] : null);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rows([
            ('اشتراک', att.text('label') ?? att.text('plan_title') ?? '—', false),
            ('پلن', att.text('plan_title') ?? '—', false),
            ('ایمیل', att.text('email') ?? '—', true),
            if (idx != null) ('شماره لینک', faNum(idx + 1), false),
          ]),
          const Gap(16),
          if (resolved != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('لینک کامل', style: t(10, c: C.n500)),
                  const Gap(4),
                  SelectableText(resolved, textDirection: TextDirection.ltr, style: t(11, c: C.n200, mono: true, h: 1.6)),
                ],
              ),
            ),
            gap,
            _btn('کپی لینک', () => copyText(resolved)),
            gap,
          ],
          if (att.text('email') != null) ...[_btn('کپی ایمیل', () => copyText(att.s('email'))), gap],
          if (links.length > 1) for (var i = 0; i < links.length; i++) ...[_LinkRow(link: links[i], highlighted: i == idx), const Gap(6)],
        ],
      );
    }

    // order
    final o = orderFresh;
    final status = o?.text('status') ?? att.text('status');
    final pending = status == 'pending';
    final hasReceipt = o?.b('has_receipt') ?? att.b('has_receipt');
    final needsBank = (o?.i('amount_toman') ?? att.i('amount_toman')) > 0;
    final canAct = widget.isAdmin && pending;
    final statusColor = switch (status) {
      'approved' || 'active' => C.emerald400,
      'pending' => C.amber400,
      'rejected' || 'expired' || 'disabled' => C.red300,
      _ => C.n400,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows([
          ('شماره', '#${faNum(o?.i('id') ?? att.i('order_id'))}', false),
          ('نوع', o?.text('kind_label') ?? att.text('kind_label') ?? '—', false),
          ('پلن / شرح', o?.text('plan_title') ?? att.text('plan_title') ?? '—', false),
          ('مبلغ', o?.text('amount_label') ?? att.text('amount_label') ?? '—', false),
          if (hasReceipt) ('رسید', 'ارسال شده ✓', false),
          if (o != null && o.i('wallet_used') > 0 && o.text('wallet_used_label') != null) ('از کیف‌پول', o.s('wallet_used_label'), false),
          if (o?.text('created_at') != null) ('تاریخ', formatDateFa(o!.text('created_at')), false),
        ]),
        gap,
        Row(
          children: [
            Text('وضعیت: ', style: t(11, c: C.n500)),
            Text(o?.text('status_label') ?? att.text('status_label') ?? '—', style: t(12, c: statusColor)),
          ],
        ),
        if (hasReceipt && orderId != null) ...[
          const Gap(12),
          Text('رسید پرداخت', style: t(11, w: 500, c: C.n300)),
          gap,
          OrderReceiptViewer(orderId: orderId!),
        ],
        if (canAct && hasReceipt) ...[
          const Gap(12),
          const Callout('این فاکتور در انتظار بررسی است — می‌توانید از همینجا تایید یا رد کنید.', tone: Tone.amber),
        ],
        if (canAct && !hasReceipt && needsBank) ...[
          const Gap(12),
          const Callout('رسید در سیستم ثبت نشده. اگر کاربر عکس را در تلگرام فرستاده، اینجا آپلود کنید یا بدون رسید تایید کنید.', tone: Tone.amber),
          gap,
          _btn(uploading ? 'در حال آپلود…' : 'آپلود رسید برای این فاکتور', uploading ? null : _uploadAdminReceipt, icon: Icons.upload_rounded),
        ],
        if (!widget.isAdmin && pending && !hasReceipt) ...[
          const Gap(12),
          const Callout('رسید پرداخت هنوز ارسال نشده — از بخش فروشگاه رسید را آپلود کنید.', tone: Tone.amber),
        ],
        const Gap(12),
        _btn('کپی شماره فاکتور', () => copyText('$orderId')),
        if (!widget.isAdmin && pending) ...[
          gap,
          _btn('رفتن به فروشگاه', () {
            Navigator.of(context).pop();
            c.switchTab(BLTab.shop);
          }, icon: Icons.open_in_new_rounded),
        ],
        if (widget.isAdmin) ...[
          gap,
          _btn('پنل ادمین', () {
            Navigator.of(context).pop();
            c.switchTab(BLTab.admin);
          }, icon: Icons.open_in_new_rounded),
        ],
        gap,
        _btn('بروزرسانی', _load, icon: Icons.refresh_rounded),
        if (canAct) ...[
          gap,
          Row(
            children: [
              Expanded(
                child: _btn(
                  'تایید فاکتور',
                  orderBusy || (!hasReceipt && needsBank) ? null : () => _orderAct(() => c.api.adminApprove(orderId!), 'فاکتور تایید شد'),
                  primary: true,
                ),
              ),
              const Gap(8),
              Expanded(
                child: _btn(
                  'رد فاکتور',
                  orderBusy ? null : () => _orderAct(() => c.api.adminReject(orderId!), 'فاکتور رد شد', close: true),
                  danger: true,
                ),
              ),
            ],
          ),
          if (!hasReceipt && needsBank) ...[
            gap,
            _btn('تایید بدون رسید (ادمین)', orderBusy ? null : () => _orderAct(() => c.api.adminApprove(orderId!), 'فاکتور تایید شد')),
          ],
        ],
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link, this.highlighted = false});

  final String link;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: highlighted ? C.w(8) : C.b(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlighted ? C.w(25) : C.w(10)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(link, textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis, style: t(10, c: C.n400, mono: true))),
            const Gap(8),
            GestureDetector(
              onTap: () => copyText(link),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: C.w(10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.copy_rounded, size: 14),
              ),
            ),
          ],
        ),
      );
}
