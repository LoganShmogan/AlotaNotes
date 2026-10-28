import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/auth_service.dart';
import 'auth/browser_auth.dart';
import 'auth/clerk_oauth.dart';
import 'config/cloud_config.dart';
import 'services/reminder_service.dart';

void main() {
  const config = CloudConfig.fromEnvironment;
  // The web build is device-only: on the web, QuillFin accounts use the
  // Next.js app (Docs/quillfin_plan.md §2).
  final clerk = config.isConfigured && !kIsWeb ? ClerkOAuth(config: config, browser: platformBrowserAuth()) : null;
  runApp(QuillFinApp(authService: QuillFinAuthService(clerk: clerk), reminders: ReminderService()));
}
