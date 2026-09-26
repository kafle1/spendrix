import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../ai.dart';
import '../format.dart';
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../widgets.dart';
import 'entry_form.dart';

const _suggestions = [
  'How much did I spend this month?',
  'Spent 300 on groceries today',
  'Rent 15000 every month',
  'Delete the last entry',
  'Who owes me money?',
];
const _maxChat = 200; // keep memory bounded on a long-running chat
const _minClip = Duration(milliseconds: 600);
const _maxClip = Duration(seconds: 30);

class _Line {
  _Line(this.text, {this.mine = false});
  final bool mine;
  String text;
  Entry? draft;
  Act? act;
  bool done = false;
  Uint8List? photo;
  bool fromMic = false;
  bool error = false;
}

/// The Ask tab: questions about your money, entries by typing, receipts from a photo.
/// The chat lives in memory only.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> with WidgetsBindingObserver {
  final _chat = <_Line>[];
  final _input = TextEditingController();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _clock = Stopwatch();
  late final Assistant _ai;
  StreamSubscription<Reply>? _answer;
  bool _recording = false;
  Timer? _recordTimer;

  String get _gb => (_ai.sizeBytes / 1e9).toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _ai = context.read<Assistant>();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // desktop reports inactive when the window only loses focus, so wait for a real background
    if (_recording && (state == AppLifecycleState.hidden || state == AppLifecycleState.paused)) _cancelRecording();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_recording) unawaited(_recorder.cancel());
    _recordTimer?.cancel();
    _recorder.dispose();
    // cancelling the subscription alone leaves the model generating unseen in the background
    _ai.stop();
    _answer?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<Assistant>();
    final store = context.watch<Store>();
    final status = ai.status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask'),
        actions: [
          if (ai.ready && _chat.isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: ai.busy ? null : () => setState(_chat.clear),
            ),
          if (ai.ready || status == AiStatus.failed)
            PopupMenuButton<bool>(
              enabled: !ai.busy,
              onSelected: (_) => _remove(ai),
              itemBuilder: (_) => const [PopupMenuItem(value: true, child: Text('Remove AI model'))],
            ),
        ],
      ),
      body: Narrow(
        child: switch (status) {
          AiStatus.unsupported => const Empty(
            icon: Icons.auto_awesome_outlined,
            title: "AI isn't available on this device",
            body: "The AI can't run on this kind of device. Everything else in the app works as usual.",
          ),
          AiStatus.checking => const Center(child: CircularProgressIndicator()),
          AiStatus.missing => _intro(ai),
          AiStatus.downloading => _downloading(ai),
          AiStatus.failed => Empty(
            icon: Icons.error_outline,
            title: 'Something went wrong',
            body: ai.error,
            action: FilledButton(onPressed: ai.retry, child: const Text('Try again')),
          ),
          _ => _chatView(ai, store),
        },
      ),
    );
  }

  Widget _intro(Assistant ai) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBubble(Icons.auto_awesome, size: 48),
                const SizedBox(height: 16),
                Text('Ask about your money', style: t.titleLarge),
                const SizedBox(height: 8),
                for (final (icon, text) in [
                  (Icons.chat_outlined, 'Answers questions like "How much did I spend on food?"'),
                  (
                    Icons.edit_note,
                    'Does things for you, like "Spent 250 on lunch", "Rent 15000 every month" or "Delete the last entry". '
                        'Nothing changes until you tap to confirm.',
                  ),
                  if (!kIsWeb) (Icons.mic_none, 'Listens when you tap the mic, in Nepali or English'),
                  if (!kIsWeb) (Icons.receipt_long_outlined, 'Reads the total from a photo of a receipt or bill'),
                  (
                    Icons.lock_outline,
                    'Private and free. It runs on this device, so your questions and photos never leave it.',
                  ),
                ])
                  ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(text)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: ai.download,
                    icon: const Icon(Icons.download),
                    label: Text('Download (about $_gb GB)'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('One-time download of about $_gb GB. Use wifi.', style: t.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _downloading(Assistant ai) {
    final t = Theme.of(context).textTheme;
    final p = ai.progress;
    final total = ai.sizeBytes / 1e6;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.downloading, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Downloading the AI', style: t.titleMedium),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: p == 0 ? null : p),
            const SizedBox(height: 8),
            Text('${(p * 100).floor()}% · ${(p * total).round()} of ${total.round()} MB', style: t.bodyMedium),
            const SizedBox(height: 8),
            Text('You can keep using the app while it downloads.', style: t.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: ai.cancelDownload, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  Widget _chatView(Assistant ai, Store store) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        if (ai.status == AiStatus.loading) ...[
          const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Getting the AI ready. The first answer takes a little longer.',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
        Expanded(
          child: _chat.isEmpty
              ? _welcome(ai)
              : LayoutBuilder(
                  builder: (context, box) => ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _chat.length,
                    itemBuilder: (context, i) => _bubble(_chat[_chat.length - 1 - i], box.maxWidth * .85, store),
                  ),
                ),
        ),
        SafeArea(top: false, child: _recording ? _recordingStrip() : _inputBar(ai)),
      ],
    );
  }

  Widget _inputBar(Assistant ai) {
    final canMedia = !kIsWeb;
    final canSend = _input.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (canMedia && _picker.supportsImageSource(ImageSource.camera))
            IconButton(
              tooltip: 'Take a photo of a receipt',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: ai.busy ? null : () => _pickPhoto(ImageSource.camera),
            ),
          if (canMedia)
            IconButton(
              tooltip: 'Choose a photo',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: ai.busy ? null : () => _pickPhoto(ImageSource.gallery),
            ),
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(_input.text),
              decoration: const InputDecoration(
                hintText: 'Ask, or type "spent 250 on lunch"',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_answer != null)
            IconButton.filledTonal(tooltip: 'Stop', icon: const Icon(Icons.stop), onPressed: ai.stop)
          else if (ai.busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (canMedia && !canSend)
            IconButton.filled(tooltip: 'Speak', icon: const Icon(Icons.mic), onPressed: _startRecording)
          else
            IconButton.filled(
              tooltip: 'Send',
              icon: const Icon(Icons.send),
              onPressed: canSend ? () => _send(_input.text) : null,
            ),
        ],
      ),
    );
  }

  Widget _recordingStrip() {
    final t = Theme.of(context).textTheme;
    final secs = _clock.elapsed.inSeconds, m = secs ~/ 60, s = secs % 60;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record, color: Theme.of(context).colorScheme.error, size: 14),
          const SizedBox(width: 8),
          Text('$m:${s.toString().padLeft(2, '0')}', style: t.bodyMedium),
          const Spacer(),
          TextButton(onPressed: _cancelRecording, child: const Text('Cancel')),
          IconButton.filled(tooltip: 'Stop', icon: const Icon(Icons.stop), onPressed: _stopRecording),
        ],
      ),
    );
  }

  Widget _welcome(Assistant ai) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: IconBubble(Icons.auto_awesome, size: 56)),
        const SizedBox(height: 16),
        Text('Ask me about your money', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          kIsWeb
              ? 'I only use the entries in this app, and it all stays on this device.'
              : 'I only use the entries in this app, and it all stays on this device. '
                    'Speak, snap a receipt, or type.',
          style: t.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              ActionChip(label: Text(s), onPressed: ai.busy || _recording ? null : () => _send(s)),
          ],
        ),
      ],
    );
  }

  Widget _bubble(_Line line, double maxWidth, Store store) {
    final c = Theme.of(context).colorScheme;
    final (bg, fg) = line.error
        ? (c.errorContainer, c.onErrorContainer)
        : line.mine
        ? (c.primaryContainer, c.onPrimaryContainer)
        : (c.surfaceContainerHighest, c.onSurface);
    final draft = line.draft;
    final photo = line.photo;
    return Align(
      alignment: line.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: line.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
                // the reply keeps the photo only to save it with the draft
                child: photo != null && line.mine
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.memory(photo, width: 160, height: 160, fit: BoxFit.cover),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: line.text.isEmpty
                            ? SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (line.fromMic) ...[Icon(Icons.mic, size: 14, color: fg), const SizedBox(width: 6)],
                                  Flexible(
                                    child: Text(line.text, style: TextStyle(color: fg)),
                                  ),
                                ],
                              ),
                      ),
              ),
              if (draft != null) _draftCard(line, store),
              if (line.act != null) _actCard(line, store),
            ],
          ),
        ),
      ),
    );
  }

  Widget _draftCard(_Line line, Store store) {
    final draft = line.draft!;
    final t = Theme.of(context).textTheme;
    // once saved, open the stored copy so later edits aren't overwritten by the draft
    final saved = store.entry(draft.id);
    final e = saved ?? draft;
    final category = store.category(e.category);
    final withPerson = e.kind == Kind.gave || e.kind == Kind.got;
    final transfer = e.kind == Kind.transfer;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBubble(
                  transfer
                      ? Icons.swap_horiz
                      : withPerson
                      ? Icons.person_outline
                      : iconOf(category?.icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.person(e.person)?.name ?? category?.name ?? e.kind.label,
                        style: t.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          transfer ? '${store.account(e.account)?.name} → ${store.account(e.to)?.name}' : e.kind.label,
                          ?e.paidIn(store.currency),
                          if (e.note.isNotEmpty) e.note,
                          dayLabel(e.date),
                        ].join(' · '),
                        style: t.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // a foreign draft with no rate yet has no home amount to show
                if (e.amount > 0) ...[
                  const SizedBox(width: 8),
                  Money(transfer ? e.amount : e.signed, colored: !transfer, style: t.titleSmall),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (saved != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Saved', style: t.labelMedium),
                  ],
                ),
              ),
            Row(
              children: saved == null
                  ? [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => openEntry(context, entry: e, photo: line.photo, guessed: true),
                          child: const Text('Edit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonal(onPressed: () => _saveDraft(line, store), child: const Text('Save')),
                      ),
                    ]
                  : [
                      Expanded(
                        child: OutlinedButton(onPressed: () => store.remove([e.id]), child: const Text('Undo')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () => openEntry(context, entry: e),
                          child: const Text('Open'),
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actCard(_Line line, Store store) {
    final act = line.act!;
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final (IconData icon, String verb) = switch (act.task) {
      Task.repeat => (Icons.repeat, 'Save'),
      Task.remove => (Icons.delete_outline, 'Delete'),
      Task.change => (Icons.edit_outlined, 'Change'),
      Task.budget => (Icons.savings_outlined, 'Confirm'),
      Task.create => (Icons.add, 'Add'),
      Task.stop => (Icons.pause_circle_outline, 'Stop'),
    };
    final repeat = act.task == Task.repeat ? act.save.first as Recurring : null;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBubble(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(act.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(act.detail, style: t.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (line.done)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: c.primary),
                    const SizedBox(width: 6),
                    Text('Done', style: t.labelMedium),
                  ],
                ),
              ),
            Row(
              children: [
                if (repeat != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      // the form saves the repeat under the same id, which also counts as done
                      onPressed: () async {
                        await openEntry(context, repeat: store.recurringOf(repeat.id) ?? repeat);
                        if (mounted) setState(() => line.done = store.recurringOf(repeat.id) != null);
                      },
                      child: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: line.done
                      ? OutlinedButton(onPressed: () => _runAct(line, store, undo: true), child: const Text('Undo'))
                      : act.task == Task.remove
                      ? FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: c.onError),
                          onPressed: () => _runAct(line, store),
                          child: Text(verb),
                        )
                      : FilledButton.tonal(onPressed: () => _runAct(line, store), child: Text(verb)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAct(_Line line, Store store, {bool undo = false}) async {
    // flip first so a double tap can't run it twice
    setState(() => line.done = !undo);
    try {
      await (undo ? line.act!.undo(store) : line.act!.apply(store));
      if (undo) {
        line.act = line.act!.again();
        if (mounted) setState(() {});
      } else {
        track('feature_used', {'name': 'ai_${line.act!.task.name}'});
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => line.done = undo);
      toast(context, "Couldn't do that. Try again.");
    }
  }

  Future<void> _saveDraft(_Line line, Store store) async {
    final draft = line.draft!;
    // a name the AI heard but isn't saved yet has to be picked or added in the form, same for a missing home amount
    final lost =
        draft.kind == Kind.transfer && (store.account(draft.account) == null || store.account(draft.to) == null);
    if ((draft.kind == Kind.gave || draft.kind == Kind.got) && draft.person == null || draft.amount == 0 || lost) {
      openEntry(context, entry: draft, photo: line.photo, guessed: true);
      return;
    }
    // a transfer already names its accounts
    final account = draft.account.isNotEmpty ? draft.account : store.defaultAccount;
    if (account == null) {
      toast(context, 'Add an account first.');
      return;
    }
    final entry = draft.copyWith(account: account, photo: line.photo != null);
    await store.save(entry);
    if (line.photo != null) await store.setPhoto(entry.id, line.photo);
    track('entry_added', {'kind': entry.kind.name, 'via': line.photo != null ? 'receipt' : 'ai'});
  }

  // last few chat messages, oldest first, for follow-ups like "and last month?"
  List<String> _recentContext([_Line? exclude]) => [
    for (final l in _chat.reversed.where((l) => l != exclude).take(2))
      if (!l.error && l.draft == null && l.act == null && l.text.isNotEmpty) l.text,
  ].reversed.toList();

  void _stream(String text, List<String> earlier, _Line reply) {
    _answer = _ai
        .ask(text, earlier: earlier)
        .listen(
          (r) => setState(() {
            reply
              ..text = r.text
              ..draft = r.draft
              ..act = r.act;
          }),
          onError: (Object e) => setState(() {
            reply
              ..text = e is AiError ? e.message : 'Something went wrong. Try again.'
              ..error = true;
          }),
          onDone: () => setState(() {
            _answer = null;
            if (reply.text.isEmpty) reply.text = 'Stopped.';
          }),
        );
  }

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty || _ai.busy || _answer != null) return;
    track('feature_used', {'name': 'ask'});
    final earlier = _recentContext();
    final reply = _Line('');
    setState(() {
      _chat
        ..add(_Line(text, mine: true))
        ..add(reply);
      if (_chat.length > _maxChat) _chat.removeRange(0, _chat.length - _maxChat);
      _input.clear();
    });
    _stream(text, earlier, reply);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    Uint8List? bytes;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      bytes = await file?.readAsBytes();
    } catch (_) {
      if (mounted) toast(context, "Couldn't open the camera or photos.");
      return;
    }
    if (bytes == null || !mounted) return;

    final reply = _Line('');
    setState(() {
      _chat
        ..add(_Line('', mine: true)..photo = bytes)
        ..add(reply);
      if (_chat.length > _maxChat) _chat.removeRange(0, _chat.length - _maxChat);
    });

    track('feature_used', {'name': 'receipt'});
    Entry? draft;
    try {
      draft = await _ai.readReceipt(bytes);
    } on AiError catch (e) {
      if (!mounted) return;
      setState(() {
        reply
          ..text = e.message
          ..error = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      if (draft == null) {
        reply.text = "I couldn't read that receipt. Try a clearer photo, or tell me the amount.";
      } else {
        reply
          ..text = "Here's a draft. Check it and save."
          ..draft = draft
          ..photo = bytes;
      }
    });
  }

  Future<void> _startRecording() async {
    if (_recording || _ai.busy) return;
    // show the strip right away so a second tap can't start another recording
    setState(() => _recording = true);
    // a stop during startup must see a zero-length clip, not the last one's time
    _clock.reset();
    String? problem;
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: '${dir.path}/spendrix_voice.wav',
        );
      } else {
        problem = 'Spendrix needs the microphone. Allow it in your settings.';
      }
    } catch (_) {
      problem = "Couldn't use the microphone.";
    }
    if (!mounted) return;
    if (problem != null) {
      setState(() => _recording = false);
      return toast(context, problem);
    }
    // cancel or stop was tapped while the mic was starting, before there was anything to stop
    if (!_recording) return _cancelRecording();
    _clock.start();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_clock.elapsed >= _maxClip) return unawaited(_stopRecording());
      setState(() {});
    });
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _clock.stop();
    if (mounted) setState(() => _recording = false);
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    _clock.stop();
    setState(() => _recording = false);
    Uint8List? bytes;
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (_clock.elapsed >= _minClip) bytes = await file.readAsBytes();
        await file.delete();
      }
    } catch (_) {}
    if (bytes == null || !mounted) return;

    final line = _Line('Listening…', mine: true)..fromMic = true;
    track('feature_used', {'name': 'voice'});
    setState(() {
      _chat.add(line);
      if (_chat.length > _maxChat) _chat.removeRange(0, _chat.length - _maxChat);
    });
    await _transcribe(line, bytes);
  }

  Future<void> _transcribe(_Line line, Uint8List wav) async {
    String text;
    try {
      text = await _ai.transcribe(wav);
    } on AiError catch (e) {
      if (!mounted) return;
      setState(() {
        line
          ..text = e.message
          ..error = true;
      });
      return;
    }
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => line.text = "I didn't catch that. Try again.");
      return;
    }
    final earlier = _recentContext(line);
    final reply = _Line('');
    setState(() {
      line.text = text;
      _chat.add(reply);
      if (_chat.length > _maxChat) _chat.removeRange(0, _chat.length - _maxChat);
    });
    _stream(text, earlier, reply);
  }

  Future<void> _remove(Assistant ai) async {
    final ok = await confirm(
      context,
      title: 'Remove the AI?',
      body:
          'This frees at least $_gb GB on this device. Your entries stay as they are, '
          'and you can download the AI again any time.',
      action: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    await ai.remove();
    if (mounted) setState(_chat.clear);
  }
}
