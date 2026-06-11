// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:webview_guardian_example/src/app_controller.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({required this.controller, super.key});

  final AppController controller;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _urlController = TextEditingController();
  String? _inputError;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(controller: controller),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filter subscriptions', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: 'Subscription URL',
                        hintText: AppController.defaultSubscriptionUrl,
                        errorText: _inputError,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addSubscription(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: controller.isUpdatingSubscriptions ? null : _addSubscription,
                          icon: const Icon(Icons.add_link),
                          label: const Text('Add subscription'),
                        ),
                        OutlinedButton.icon(
                          onPressed: controller.restoreDefaultSubscription,
                          icon: const Icon(Icons.restore),
                          label: const Text('Restore EasyList'),
                        ),
                        OutlinedButton.icon(
                          onPressed: controller.clearCache,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Clear cache'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (controller.subscriptionUrls.isEmpty)
                      const Text('No subscriptions added. Add at least one URL to build rules.')
                    else
                      ...controller.subscriptionUrls.map(
                        (url) => _SubscriptionTile(
                          url: url,
                          onRemove: () => controller.removeSubscription(url),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addSubscription() async {
    final error = await widget.controller.addSubscription(_urlController.text);
    if (!mounted) return;

    setState(() => _inputError = error);
    if (error == null) {
      _urlController.clear();
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Ad blocker', style: textTheme.titleLarge)),
                Switch(value: controller.isEnabled, onChanged: controller.setAdblockEnabled),
              ],
            ),
            const SizedBox(height: 8),
            _MetricRow(label: 'Engine', value: controller.isReady ? 'Ready' : 'Loading'),
            _MetricRow(label: 'Rules', value: '${controller.ruleCount}'),
            _MetricRow(label: 'Subscriptions', value: '${controller.subscriptionUrls.length}'),
            if (controller.adblockDirectoryPath case final path?)
              _MetricRow(label: 'Storage', value: path),
            if (controller.statusMessage case final message?) ...[
              const SizedBox(height: 8),
              Text(message, style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: const Icon(Icons.link),
        title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: 'Remove subscription',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}
