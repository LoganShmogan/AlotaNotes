import 'package:flutter/material.dart';

Future<String?> promptForName(BuildContext context, {required String title, String initialValue = ''}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
      ],
    ),
  );
}
