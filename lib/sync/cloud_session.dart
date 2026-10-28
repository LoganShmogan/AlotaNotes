/// Everything a signed-in screen needs from the backend: the account, the
/// Convex client, sync, and the plan. Provided by RootShell through
/// [CloudScope]; absent for a device-only session.
library;

import 'package:flutter/widgets.dart';

import '../ai/base.dart';
import '../auth/auth_service.dart';
import 'convex_client.dart';
import 'sync_service.dart';

/// What `billing:me` returns (Docs/backend.md, "Plans and usage").
class PlanInfo {
  final String plan;
  final String planName;
  final int aiNotesUsed;
  final int aiNotesLimit;
  final String? subscriptionStatus;
  final String? interval;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final bool upgradeAvailable;

  const PlanInfo({
    required this.plan,
    required this.planName,
    required this.aiNotesUsed,
    required this.aiNotesLimit,
    this.subscriptionStatus,
    this.interval,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.upgradeAvailable = false,
  });

  bool get isPro => plan == 'pro';

  factory PlanInfo.fromJson(Map<String, dynamic> json) {
    final ai = Map<String, dynamic>.from(json['aiNotes'] as Map);
    final sub = json['subscription'] == null ? null : Map<String, dynamic>.from(json['subscription'] as Map);
    final end = sub?['currentPeriodEnd'] as num?;
    return PlanInfo(
      plan: json['plan'] as String,
      planName: json['planName'] as String,
      aiNotesUsed: (ai['used'] as num).toInt(),
      aiNotesLimit: (ai['limit'] as num).toInt(),
      subscriptionStatus: sub?['status'] as String?,
      interval: sub?['interval'] as String?,
      currentPeriodEnd: end == null ? null : DateTime.fromMillisecondsSinceEpoch(end.toInt(), isUtc: true),
      cancelAtPeriodEnd: sub?['cancelAtPeriodEnd'] == true,
      upgradeAvailable: json['upgradeAvailable'] == true,
    );
  }
}

class CloudSession {
  final AppUser user;
  final ConvexClient client;
  final SyncService sync;

  const CloudSession({required this.user, required this.client, required this.sync});

  Future<PlanInfo> plan() async => PlanInfo.fromJson(Map<String, dynamic>.from(await client.query('billing:me') as Map));

  /// A Stripe Checkout page for Pro, billed monthly or yearly.
  Future<Uri> checkoutUrl({required bool yearly}) async {
    final result = await client.action('stripeActions:createCheckoutSession', {'interval': yearly ? 'year' : 'month'});
    return Uri.parse((result as Map)['url'] as String);
  }

  /// Stripe's Billing Portal, to change or cancel the plan.
  Future<Uri> portalUrl() async {
    final result = await client.action('stripeActions:createPortalSession');
    return Uri.parse((result as Map)['url'] as String);
  }
}

/// Holds the current session for [CloudScope].
class CloudSessionHolder extends ValueNotifier<CloudSession?> {
  CloudSessionHolder() : super(null);

  bool _disposed = false;

  /// Clears [session] if it's still the current one. Deferred, because the
  /// shell ends its session while being unmounted, when the tree is locked;
  /// by then the whole app may be gone too.
  void clearLater(CloudSession session) {
    Future.microtask(() {
      if (!_disposed && value == session) value = null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Makes the current [CloudSession] visible to every route. It sits above
/// the Navigator (QuillFinApp's `MaterialApp.builder`), so pages pushed from
/// the shell see it too; RootShell fills it in once the session starts.
class CloudScope extends InheritedNotifier<CloudSessionHolder> {
  const CloudScope({super.key, required CloudSessionHolder super.notifier, required super.child});

  /// The signed-in session, or null when device-only (or still starting).
  static CloudSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloudScope>()?.notifier?.value;

  /// The holder RootShell publishes its session to, if any.
  static CloudSessionHolder? holderOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CloudScope>()?.notifier;
}

/// Generates questions on QuillFin's own key, within the plan's monthly
/// allowance (backend/convex/ai.ts). Used when signed in without an API key
/// of your own.
class QuillFinAIProvider extends AIProvider {
  final ConvexClient client;

  QuillFinAIProvider(this.client) : super(apiKey: '', model: 'quillfin');

  @override
  Future<List<GeneratedQuestion>> generateQuestions(
    String noteText, {
    int numQuestions = 5,
    String questionFormat = 'short_answer',
    List<LinkedNoteContext>? linkedNotesContext,
  }) async {
    final dynamic result;
    try {
      result = await client.action('ai:generateQuestions', {
        'noteText': noteText,
        'numQuestions': numQuestions,
        'questionFormat': questionFormat,
        if (linkedNotesContext != null && linkedNotesContext.isNotEmpty)
          'linkedNotes': [
            for (final n in linkedNotesContext)
              {'title': n.title, 'excerpt': n.excerpt, 'sharedKeywords': n.sharedKeywords},
          ],
      });
    } on ConvexException catch (e) {
      throw AIProviderError(e.message);
    }
    return [
      for (final raw in (result as Map)['questions'] as List)
        GeneratedQuestion(
          questionType: raw['questionType'] as String,
          prompt: raw['prompt'] as String,
          expectedAnswer: raw['expectedAnswer'] as String,
          choices: (raw['choices'] as List?)?.cast<String>(),
          correctChoiceIndex: (raw['correctChoiceIndex'] as num?)?.toInt(),
        ),
    ];
  }
}
