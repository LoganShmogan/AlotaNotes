/// Settings > Sync and Settings > Plan, shown when signed in to a QuillFin
/// account.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../sync/cloud_session.dart';
import '../../sync/convex_client.dart';
import '../../sync/sync_service.dart';
import '../../theme/theme.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _date(DateTime d) {
  final local = d.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

String _ago(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return _date(at);
}

class SyncPanel extends StatelessWidget {
  final CloudSession session;
  const SyncPanel({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: session.sync,
      builder: (context, status, _) {
        final syncing = status.phase == SyncPhase.syncing;
        final last = status.lastSyncedAt;
        final String summary;
        if (syncing) {
          summary = 'Syncing...';
        } else if (last == null) {
          summary = 'Not synced yet';
        } else {
          summary = 'Last synced ${_ago(last, DateTime.now().toUtc())}';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(status.phase == SyncPhase.error ? Icons.sync_problem : Icons.cloud_done_outlined),
              title: Text(summary),
              subtitle: Text(
                status.pendingChanges == 0
                    ? 'Everything on this device is in your account (${session.user.email ?? session.user.displayName}).'
                    : '${status.pendingChanges} change${status.pendingChanges == 1 ? '' : 's'} waiting to sync.',
              ),
              trailing: syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: session.sync.syncNow, child: const Text('Sync now')),
            ),
            if (status.error != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                title: Text(status.error!),
                subtitle: status.errorCode == ConvexException.networkError
                    ? const Text("Your changes are safe on this device and will sync when you're back online.")
                    : null,
              ),
            if (status.oversizedNotes > 0)
              ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(
                  '${status.oversizedNotes} note${status.oversizedNotes == 1 ? ' is' : 's are'} over 200 KB '
                  "and won't sync",
                ),
                subtitle: const Text('Split long notes into smaller ones to sync them.'),
              ),
          ],
        );
      },
    );
  }
}

class PlanPanel extends StatefulWidget {
  final CloudSession session;

  /// Whether this is an iOS build, where Apple's rules keep upgrading out of
  /// the app (Docs/quillfin_plan.md §2). Overridable for tests.
  final bool? isIOS;

  const PlanPanel({super.key, required this.session, this.isIOS});

  @override
  State<PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends State<PlanPanel> with WidgetsBindingObserver {
  late Future<PlanInfo> _plan = widget.session.plan();
  bool _opening = false;

  bool get _isIOS => widget.isIOS ?? (!kIsWeb && Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Stripe in the browser: show the new plan.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  void _reload() {
    setState(() {
      _plan = widget.session.plan();
    });
  }

  Future<void> _open(Future<Uri> Function() url) async {
    setState(() => _opening = true);
    try {
      final opened = await launchUrl(await url(), mode: LaunchMode.externalApplication);
      if (!opened) throw const ConvexException('BROWSER', "Couldn't open the browser.");
    } on ConvexException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlanInfo>(
      future: _plan,
      builder: (context, snapshot) {
        // A reload keeps showing the plan it has, but not a stale error.
        final reloading = snapshot.connectionState == ConnectionState.waiting;
        if (reloading && !snapshot.hasData) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(snapshot.error is ConvexException ? '${snapshot.error}' : "Couldn't load your plan."),
            trailing: TextButton(onPressed: _reload, child: const Text('Retry')),
          );
        }
        return _buildPlan(context, snapshot.data!);
      },
    );
  }

  Widget _buildPlan(BuildContext context, PlanInfo plan) {
    final textTheme = Theme.of(context).textTheme;
    final usage = plan.aiNotesLimit == 0 ? 0.0 : (plan.aiNotesUsed / plan.aiNotesLimit).clamp(0.0, 1.0);
    final end = plan.currentPeriodEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(plan.isPro ? Icons.workspace_premium : Icons.workspace_premium_outlined),
          title: Text('QuillFin ${plan.planName}', style: textTheme.titleMedium),
          subtitle: Text(switch ((plan.isPro, end, plan.cancelAtPeriodEnd)) {
            (true, final DateTime end, true) => 'Ends on ${_date(end)}',
            (true, final DateTime end, false) => 'Renews on ${_date(end)}${plan.interval == null ? '' : ' (${plan.interval}ly)'}',
            (true, _, _) => 'Active',
            _ => 'Your own AI key is always unlimited. Pro raises the allowance on QuillFin\'s AI.',
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text("QuillFin's AI this month: ${plan.aiNotesUsed} of ${plan.aiNotesLimit} notes"),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: LinearProgressIndicator(value: usage, color: usage >= 1 ? context.brand.danger : null),
        ),
        const SizedBox(height: 12),
        if (plan.isPro && !_isIOS)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: _opening ? null : () => _open(widget.session.portalUrl),
              child: const Text('Manage plan'),
            ),
          )
        else if (!plan.isPro && plan.upgradeAvailable && !_isIOS)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _opening ? null : () => _open(() => widget.session.checkoutUrl(yearly: false)),
                  child: const Text('Upgrade monthly'),
                ),
                OutlinedButton(
                  onPressed: _opening ? null : () => _open(() => widget.session.checkoutUrl(yearly: true)),
                  child: const Text('Upgrade yearly'),
                ),
              ],
            ),
          )
        else if (_isIOS)
          const ListTile(subtitle: Text('Plans are managed on the QuillFin website.')),
      ],
    );
  }
}
