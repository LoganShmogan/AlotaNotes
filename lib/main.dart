import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/auth_service.dart';
import 'services/reminder_service.dart';

void main() {
  runApp(QuizApp(authService: HardcodedAuthService(), reminders: ReminderService()));
}
