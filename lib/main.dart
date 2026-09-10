import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/auth_service.dart';

void main() {
  runApp(QuizApp(authService: HardcodedAuthService()));
}
