import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../storage/problems_repo.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';

/// Add a problem to the tracker, or edit one ([problemId] set). Pops with
/// the saved problem's id, or null if backed out.
class ProblemEditorScreen extends StatefulWidget {
  final Database db;
  final int? problemId;
  const ProblemEditorScreen({super.key, required this.db, this.problemId});

  @override
  State<ProblemEditorScreen> createState() => _ProblemEditorScreenState();
}

class _ProblemEditorScreenState extends State<ProblemEditorScreen> {
  late final ProblemsRepo _repo = ProblemsRepo(widget.db);
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _platform = TextEditingController();
  final _tags = TextEditingController();
  final _solution = TextEditingController();
  final _notes = TextEditingController();
  String _difficulty = problemDifficultyMedium;
  bool _loading = true;
  String? _error;

  bool get _isNew => widget.problemId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isNew) {
      final p = await _repo.get(widget.problemId!);
      _title.text = p.title;
      _url.text = p.url ?? '';
      _platform.text = p.platform;
      _tags.text = p.tags.join(', ');
      _solution.text = p.solution;
      _notes.text = p.notes;
      _difficulty = p.difficulty;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the problem a name.');
      return;
    }
    final tags = _tags.text.split(',');
    final Problem saved;
    if (_isNew) {
      final url = _url.text.trim();
      saved = await _repo.create(
        title,
        difficulty: _difficulty,
        url: url.isEmpty ? null : url,
        platform: _platform.text.trim(),
        tags: tags,
        solution: _solution.text,
        notes: _notes.text,
      );
    } else {
      saved = await _repo.update(
        widget.problemId!,
        title: title,
        difficulty: _difficulty,
        url: _url.text.trim(),
        platform: _platform.text.trim(),
        tags: tags,
        solution: _solution.text,
        notes: _notes.text,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(saved.id);
  }

  @override
  void dispose() {
    for (final c in [_title, _url, _platform, _tags, _solution, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New problem' : 'Edit problem'),
        actions: [IconButton(icon: const Icon(Icons.save), tooltip: 'Save', onPressed: _loading ? null : _save)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  autofocus: _isNew,
                  decoration: InputDecoration(labelText: 'Problem name', errorText: _error),
                  textInputAction: TextInputAction.next,
                ),
                const SectionLabel('Difficulty'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (value, label) in [
                      (problemDifficultyEasy, 'Easy'),
                      (problemDifficultyMedium, 'Medium'),
                      (problemDifficultyHard, 'Hard'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _difficulty == value,
                        onSelected: (_) => setState(() => _difficulty = value),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Link (optional)', hintText: 'https://leetcode.com/problems/...'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _platform,
                  decoration: const InputDecoration(labelText: 'Platform (optional)', hintText: 'LeetCode, HackerRank, textbook...'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(labelText: 'Tags, comma separated', hintText: 'arrays, two pointers'),
                ),
                const SectionLabel('Your solution'),
                TextField(
                  controller: _solution,
                  minLines: 6,
                  maxLines: null,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: colorInk),
                  decoration: const InputDecoration(hintText: 'Paste your code or describe the approach'),
                ),
                const SectionLabel('Notes'),
                TextField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: null,
                  decoration: const InputDecoration(hintText: 'Key insight, gotchas, complexity...'),
                ),
                const SizedBox(height: 24),
                PixelButton(label: _isNew ? 'Add problem' : 'Save changes', onPressed: _save),
              ],
            ),
    );
  }
}
