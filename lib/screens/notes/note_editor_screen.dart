import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../../ai/base.dart';
import '../../ai/provider_factory.dart';
import '../../core/text_extraction.dart';
import '../../layout/breakpoints.dart';
import '../../services/question_generation_service.dart';
import '../../settings/app_settings.dart';
import '../../storage/notes_repo.dart';
import '../../storage/questions_repo.dart';
import '../../sync/cloud_session.dart';
import 'note_questions_screen.dart';

typedef ProviderBuilder = AIProvider Function(String providerName, String apiKey, String model, String? baseUrl);

class NoteEditorScreen extends StatefulWidget {
  final Database db;
  final int noteId;
  // Injectable so widget tests can generate questions without a real HTTP
  // call; the app always uses the default.
  final ProviderBuilder providerBuilder;

  /// Called after a save, so a list showing this note can refresh its title.
  final VoidCallback? onSaved;

  /// True when shown as the detail pane of a folder's list-detail layout,
  /// where there's nothing to go back to.
  final bool embedded;

  const NoteEditorScreen({
    super.key,
    required this.db,
    required this.noteId,
    this.providerBuilder = buildProvider,
    this.onSaved,
    this.embedded = false,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final NotesRepo _notesRepo = NotesRepo(widget.db);
  late final QuestionsRepo _questionsRepo = QuestionsRepo(widget.db);
  final _secureStorage = const FlutterSecureStorage();
  final _settingsStore = const AppSettingsStore();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final note = await _notesRepo.get(widget.noteId);
    _titleController.text = note.title;
    _bodyController.text = note.body;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _notesRepo.update(widget.noteId, title: _titleController.text.trim(), body: _bodyController.text);
    widget.onSaved?.call();
    if (mounted) setState(() => _saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions.map((e) => e.substring(1)).toList(),
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return; // user cancelled

    try {
      final text = extractText(file.name, file.bytes!);
      _bodyController.text = text;
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = file.name;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imported.')));
    } on UnsupportedFileTypeError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unsupported file: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _generateQuestions() async {
    setState(() => _generating = true);
    try {
      final cloud = CloudScope.maybeOf(context);
      final apiKey = await _secureStorage.read(key: 'ai_api_key');
      final settings = await _settingsStore.load();
      final AIProvider provider;
      if (apiKey != null && apiKey.isNotEmpty) {
        provider = widget.providerBuilder(settings.provider, apiKey, settings.model, settings.baseUrl);
      } else if (cloud != null) {
        // Signed in without a key of your own: QuillFin's AI, within the plan.
        provider = QuillFinAIProvider(cloud.client);
      } else {
        throw const AIProviderError('No API key configured. Add one in the Account tab.');
      }
      final service = QuestionGenerationService(
        notesRepo: _notesRepo,
        questionsRepo: _questionsRepo,
        provider: provider,
        defaultQuestionFormat: settings.defaultQuestionFormat,
      );
      final created = await service.generateForNote(widget.noteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generated ${created.length} question(s).')));
    } on AIProviderError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Question generation failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
            tooltip: 'View questions generated from this note',
            icon: const Icon(Icons.quiz_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NoteQuestionsScreen(db: widget.db, noteId: widget.noteId),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Import file (.txt/.md/.pdf/.docx/.pptx)',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importFile,
          ),
          TextButton.icon(
            onPressed: _generating ? null : _generateQuestions,
            icon: _generating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: const Text('Generate'),
          ),
          IconButton(
            tooltip: 'Save (Ctrl+S)',
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          // Capped at a comfortable line length on wide panes.
          : ContentWidth(
              maxWidth: 760,
              child: Padding(
                padding: EdgeInsets.all(context.windowSize.gutter),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TextField(
                        controller: _bodyController,
                        decoration: const InputDecoration(labelText: 'Body', alignLabelWithHint: true),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
