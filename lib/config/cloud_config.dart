/// Build-time settings for accounts and sync, from `--dart-define` (or
/// `--dart-define-from-file=config/<env>.json`, see config/example.json).
/// Only publishable values belong here: secrets live in Convex
/// (Docs/backend.md). With nothing set, the app runs device-only: the
/// sign-in screen offers only "Continue on this device".
library;

class CloudConfig {
  /// Clerk's Frontend API host, e.g. `clerk.quillfin.app` or
  /// `xyz.clerk.accounts.dev`. A scheme is optional.
  final String clerkDomain;

  /// The client id of Clerk's OAuth application for this app.
  final String clerkClientId;

  /// The Convex deployment URL, `https://<name>.convex.cloud`.
  final String convexUrl;

  /// The web app, where iOS users manage their plan (see Docs/quillfin_plan.md §2).
  final String siteUrl;

  const CloudConfig({
    required this.clerkDomain,
    required this.clerkClientId,
    required this.convexUrl,
    this.siteUrl = '',
  });

  static const fromEnvironment = CloudConfig(
    clerkDomain: String.fromEnvironment('QUILLFIN_CLERK_DOMAIN'),
    clerkClientId: String.fromEnvironment('QUILLFIN_CLERK_CLIENT_ID'),
    convexUrl: String.fromEnvironment('QUILLFIN_CONVEX_URL'),
    siteUrl: String.fromEnvironment('QUILLFIN_SITE_URL'),
  );

  bool get isConfigured => clerkDomain.isNotEmpty && clerkClientId.isNotEmpty && convexUrl.isNotEmpty;

  Uri get clerkBase => Uri.parse(clerkDomain.contains('://') ? clerkDomain : 'https://$clerkDomain');

  Uri get convexDeployment => Uri.parse(convexUrl);
}
