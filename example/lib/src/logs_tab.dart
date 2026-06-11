// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:webview_guardian_example/src/app_controller.dart';

class LogsTab extends StatefulWidget {
  const LogsTab({required this.controller, super.key});

  final AppController controller;

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  final Set<LogEntryKind> _selectedKinds = Set.of(LogEntryKind.values);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final filteredLogs = widget.controller.logs
            .where((entry) => _selectedKinds.contains(entry.kind))
            .toList(growable: false);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(child: _MetricsGrid(controller: widget.controller)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverToBoxAdapter(
                child: _LogFilterChips(
                  selectedKinds: _selectedKinds,
                  onChanged: _toggleKind,
                ),
              ),
            ),
            if (widget.controller.logs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Events will appear here after the engine starts.')),
              )
            else if (filteredLogs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No logs match the selected filters.')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList.separated(
                  itemCount: filteredLogs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _LogTile(entry: filteredLogs[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  void _toggleKind(LogEntryKind kind, bool selected) {
    setState(() {
      if (selected) {
        _selectedKinds.add(kind);
      } else {
        _selectedKinds.remove(kind);
      }
    });
  }
}

class _LogFilterChips extends StatelessWidget {
  const _LogFilterChips({required this.selectedKinds, required this.onChanged});

  final Set<LogEntryKind> selectedKinds;
  final void Function(LogEntryKind kind, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: LogEntryKind.values.map((kind) {
        return FilterChip(
          label: Text(_labelForKind(kind)),
          selected: selectedKinds.contains(kind),
          onSelected: (selected) => onChanged(kind, selected),
        );
      }).toList(),
    );
  }

  String _labelForKind(LogEntryKind kind) {
    return switch (kind) {
      LogEntryKind.info => 'Info',
      LogEntryKind.success => 'Success',
      LogEntryKind.blocked => 'Blocked',
      LogEntryKind.allowed => 'Allowed',
      LogEntryKind.error => 'Errors',
    };
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final metrics = [
      _Metric('Blocked', '${controller.blockedRequests}', Icons.block, Colors.red),
      _Metric('Allowed', '${controller.allowedRequests}', Icons.check_circle_outline, Colors.green),
      _Metric(
        'CSS injections',
        '${controller.cosmeticInjections}',
        Icons.brush_outlined,
        Colors.indigo,
      ),
      _Metric('Scriptlets', '${controller.scriptletInjections}', Icons.code, Colors.orange),
      _Metric('Rules', '${controller.ruleCount}', Icons.rule, Colors.blue),
      _Metric('Log entries', '${controller.logs.length}', Icons.receipt_long, Colors.blueGrey),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 3 : 2,
        childAspectRatio: isWide ? 3.4 : 2.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) => _MetricCard(metric: metrics[index]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: metric.color.withValues(alpha: 0.12),
              foregroundColor: metric.color,
              child: Icon(metric.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metric.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(metric.value, style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.kind) {
      LogEntryKind.info => Theme.of(context).colorScheme.primary,
      LogEntryKind.success => Colors.green,
      LogEntryKind.blocked => Colors.red,
      LogEntryKind.allowed => Colors.teal,
      LogEntryKind.error => Theme.of(context).colorScheme.error,
    };
    final icon = switch (entry.kind) {
      LogEntryKind.info => Icons.info_outline,
      LogEntryKind.success => Icons.check_circle_outline,
      LogEntryKind.blocked => Icons.block,
      LogEntryKind.allowed => Icons.check,
      LogEntryKind.error => Icons.error_outline,
    };

    return Card.outlined(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(entry.title),
        subtitle: Text(entry.details, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: Text(_formatTime(entry.timestamp)),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}
