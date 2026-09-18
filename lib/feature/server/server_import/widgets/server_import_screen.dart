import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/extensions/locale_enum_extension.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/server_import/service/local_import_session.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

typedef LocalImportSessionFactory =
    Future<LocalImportSession> Function({
      required Future<void> Function(String link) onImport,
    });

class ServerImportScreen extends StatefulWidget {
  final Future<ServerData> Function(String link) decode;
  final Future<void> Function(ServerData data) save;
  final LocalImportSessionFactory sessionFactory;

  const ServerImportScreen({
    super.key,
    required this.decode,
    required this.save,
    this.sessionFactory = LocalImportSession.start,
  });

  @override
  State<ServerImportScreen> createState() => _ServerImportScreenState();
}

enum _ImportPhase { starting, waiting, expired, unavailable, review }

class _ServerImportScreenState extends State<ServerImportScreen> with WidgetsBindingObserver {
  final _primaryFocus = FocusNode();
  LocalImportSession? _session;
  Timer? _countdownTimer;
  ServerData? _candidate;
  _ImportPhase _phase = _ImportPhase.starting;
  bool _invalidLink = false;
  bool _saving = false;
  bool _saveFailed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startSession());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _suspendSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _suspendSession();
    }
  }

  void _closeSession() {
    _generation++;
    _countdownTimer?.cancel();
    final session = _session;
    if (session != null) unawaited(session.close());
  }

  void _suspendSession() {
    if (_phase != _ImportPhase.waiting && _phase != _ImportPhase.starting) return;
    _closeSession();
    setState(() => _phase = _ImportPhase.expired);
    _focusPrimary();
  }

  Future<void> _startSession() async {
    final generation = ++_generation;
    _countdownTimer?.cancel();
    final previous = _session;
    _session = null;
    setState(() {
      _phase = _ImportPhase.starting;
      _invalidLink = false;
      _candidate = null;
    });
    await previous?.close();
    if (!mounted || generation != _generation) return;

    try {
      final session = await widget.sessionFactory(
        onImport: (link) => _receiveLink(link, generation),
      );
      if (!mounted || generation != _generation) {
        await session.close();
        return;
      }

      setState(() {
        _session = session;
        _phase = _ImportPhase.waiting;
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _phase == _ImportPhase.waiting) setState(() {});
      });
      unawaited(
        session.done.then((reason) {
          if (!mounted || generation != _generation) return;
          _countdownTimer?.cancel();
          if (reason == LocalImportSessionEndReason.expired) {
            setState(() => _phase = _ImportPhase.expired);
            _focusPrimary();
          } else if (reason == LocalImportSessionEndReason.closed && _phase == _ImportPhase.waiting) {
            setState(() => _phase = _ImportPhase.unavailable);
            _focusPrimary();
          }
        }),
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _phase = _ImportPhase.unavailable);
      _focusPrimary();
    }
  }

  Future<void> _receiveLink(String link, int generation) async {
    try {
      final data = await widget.decode(link);
      if (!mounted || generation != _generation || (_session?.isClosed ?? true)) {
        throw StateError('Import session closed');
      }
      _countdownTimer?.cancel();
      setState(() {
        _candidate = data;
        _phase = _ImportPhase.review;
        _invalidLink = false;
        _saveFailed = false;
      });
      _focusPrimary();
    } catch (_) {
      if (mounted && generation == _generation && !(_session?.isClosed ?? true)) {
        setState(() => _invalidLink = true);
      }
      // Keep exceptions and submitted credentials out of UI and HTTP responses.
      throw const FormatException('This server link could not be imported.');
    }
  }

  Future<void> _save() async {
    final data = _candidate;
    if (data == null || _saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.save(data);
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
      _focusPrimary();
    }
  }

  void _focusPrimary() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _primaryFocus.requestFocus();
    });
  }

  void _cancel() {
    if (!_saving) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _closeSession();
    },
    child: ScaffoldWrapper(
      child: Scaffold(
        appBar: CustomAppBar(
          title: context.ln.importFromPhone,
          leadingIconType: AppBarLeadingIconType.back,
          onBackPressed: _cancel,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: switch (_phase) {
                _ImportPhase.waiting => _waitingContent(context),
                _ImportPhase.review => _reviewContent(context),
                _ => _statusContent(context),
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _waitingContent(BuildContext context) {
    final session = _session!;
    final qr = Semantics(
      label: context.ln.importFromPhone,
      image: true,
      child: ExcludeSemantics(
        child: QrImageView(
          data: session.qrUrl.toString(),
          size: 220,
          padding: const EdgeInsets.all(12),
          backgroundColor: Colors.white,
        ),
      ),
    );
    final instructions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.ln.importOnSameNetwork, style: context.textTheme.bodyLarge),
        const SizedBox(height: 16),
        Text(session.url.toString(), style: context.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(context.ln.importPairingCode(session.pairingCode), style: context.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(context.ln.importExpiresIn(_remainingTime(session.expiresAt)), style: context.textTheme.bodyMedium),
        if (_invalidLink) ...[
          const SizedBox(height: 12),
          _error(context, context.ln.importInvalidLink),
        ],
        const SizedBox(height: 20),
        FilledButton(
          focusNode: _primaryFocus,
          autofocus: true,
          onPressed: _cancel,
          child: Text(context.ln.importCancel),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 600
          ? Row(
              children: [
                qr,
                const SizedBox(width: 32),
                Expanded(child: instructions),
              ],
            )
          : Column(
              children: [
                qr,
                const SizedBox(height: 20),
                instructions,
              ],
            ),
    );
  }

  Widget _reviewContent(BuildContext context) {
    final data = _candidate!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.ln.importReceived, style: context.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(context.ln.importConfirmServer, style: context.textTheme.bodyMedium),
        const SizedBox(height: 20),
        _detail(context, context.ln.serverName, data.name),
        _detail(context, context.ln.enterIpAddressLabel, data.ipAddress),
        _detail(context, context.ln.enterDomainLabel, data.domain),
        _detail(context, context.ln.protocol, data.vpnProtocol.localized(context)),
        if (_saveFailed) ...[
          const SizedBox(height: 12),
          _error(context, context.ln.importSaveError),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            FilledButton(
              focusNode: _primaryFocus,
              autofocus: true,
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_saveFailed ? context.ln.importRetry : context.ln.add),
            ),
            const SizedBox(width: 16),
            TextButton(onPressed: _saving ? null : _cancel, child: Text(context.ln.importCancel)),
          ],
        ),
      ],
    );
  }

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 180, child: Text(label, style: context.textTheme.bodyMedium)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(value, style: context.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  Widget _statusContent(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_phase == _ImportPhase.starting) ...[
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
      ],
      Text(
        switch (_phase) {
          _ImportPhase.starting => context.ln.importStarting,
          _ImportPhase.expired => context.ln.importExpired,
          _ => context.ln.importNetworkError,
        },
        textAlign: TextAlign.center,
        style: context.textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_phase != _ImportPhase.starting) ...[
            FilledButton(
              focusNode: _primaryFocus,
              autofocus: true,
              onPressed: _startSession,
              child: Text(context.ln.importRetry),
            ),
            const SizedBox(width: 16),
          ],
          TextButton(
            focusNode: _phase == _ImportPhase.starting ? _primaryFocus : null,
            autofocus: _phase == _ImportPhase.starting,
            onPressed: _cancel,
            child: Text(context.ln.importCancel),
          ),
        ],
      ),
    ],
  );

  Widget _error(BuildContext context, String message) => Semantics(
    liveRegion: true,
    child: Text(message, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.error)),
  );

  String _remainingTime(DateTime expiresAt) {
    final seconds = (expiresAt.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    final remaining = seconds < 0 ? 0 : seconds;
    return '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeSession();
    _primaryFocus.dispose();
    super.dispose();
  }
}
