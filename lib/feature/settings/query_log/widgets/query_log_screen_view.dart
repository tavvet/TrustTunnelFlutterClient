import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/vpn_log.dart';
import 'package:trusttunnel/feature/settings/query_log/widgets/query_log_card.dart';
import 'package:trusttunnel/feature/settings/query_log/widgets/query_log_empty_placeholder.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

class QueryLogScreenView extends StatefulWidget {
  const QueryLogScreenView({super.key});

  @override
  State<QueryLogScreenView> createState() => _QueryLogScreenViewState();
}

class _QueryLogScreenViewState extends State<QueryLogScreenView> {
  List<VpnLog> _logs = [];

  late final ScrollController _scrollController;
  final FocusNode _logFocusNode = FocusNode(debugLabel: 'Connection log');

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final logController = VpnScope.logsControllerOf(context);

    if (!listEquals(logController.logs, _logs)) {
      _logs = [...logController.logs];
    }
  }

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: Scaffold(
      appBar: CustomAppBar(
        title: context.ln.connectionLog,
      ),
      body: _logs.isEmpty ? const QueryLogEmptyPlaceholder() : _buildLogList(context),
    ),
  );

  Widget _buildLogList(BuildContext context) {
    final list = _QueryLogListView(logs: _logs, controller: _scrollController);
    if (MediaQuery.navigationModeOf(context) != NavigationMode.directional) {
      return list;
    }

    // Log entries are read-only, so the list itself needs a focus stop for a
    // remote. Keep left/right available for returning to the navigation rail.
    return Focus(
      focusNode: _logFocusNode,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: _onLogKey,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: Border.all(
              color: _logFocusNode.hasFocus ? context.colors.accent : Colors.transparent,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(3),
          child: list,
        ),
      ),
    );
  }

  KeyEventResult _onLogKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if ((key != LogicalKeyboardKey.arrowUp && key != LogicalKeyboardKey.arrowDown) || !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }

    final position = _scrollController.position;
    // This list is reversed: moving visually upward increases its offset.
    final delta = position.viewportDimension * (key == LogicalKeyboardKey.arrowUp ? 0.6 : -0.6);
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return KeyEventResult.ignored;
    _scrollController.animateTo(target, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _logFocusNode.dispose();
    super.dispose();
  }
}

class _QueryLogListView extends StatelessWidget {
  final ScrollController? controller;
  final List<VpnLog> logs;

  const _QueryLogListView({
    this.controller,
    required this.logs,
  });

  @override
  Widget build(BuildContext context) => ListView.separated(
    controller: controller,
    reverse: true,
    shrinkWrap: logs.length < 50,
    itemBuilder: (context, index) {
      final log = logs[index];

      return QueryLogCard(
        key: ValueKey(log.timeStamp.microsecondsSinceEpoch),
        log: log,
      );
    },
    separatorBuilder: (_, _) => const Divider(),
    itemCount: logs.length,
  );
}
