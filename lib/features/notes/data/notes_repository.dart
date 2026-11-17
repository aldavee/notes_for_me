import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:notes_for_me/features/notes/domain/entities/note_item.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotesRepository extends ChangeNotifier {
  NotesRepository({
    Future<SharedPreferences> Function()? prefsProvider,
    Future<Directory?> Function()? directoryProvider,
  })  : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _directoryProvider = directoryProvider ?? _defaultDirectoryProvider;

  static final NotesRepository instance = NotesRepository();

  static const String _prefsNotesKey = 'notes_for_me_notes_v1';
  static const String _prefsFoldersKey = 'notes_for_me_folders_v1';
  static const String _prefsSeededKey = 'notes_for_me_seeded_v1';
  static const List<String> defaultFolders = [
    'Personal',
    'Work',
    'Ideas',
    'Study',
  ];

  final Future<SharedPreferences> Function() _prefsProvider;
  final Future<Directory?> Function() _directoryProvider;

  List<NoteItem> _allNotes = <NoteItem>[];
  List<String> _folders = List<String>.from(defaultFolders);
  bool _initialized = false;

  static Future<Directory?> _defaultDirectoryProvider() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  bool get isInitialized => _initialized;
  List<String> get folders => List.unmodifiable(_folders);

  List<NoteItem> get activeNotes => _sortNotes(
        _allNotes
            .where((n) => !n.isDeletedPermanently && !n.isTrashed && !n.isArchived)
            .toList(),
      );

  List<NoteItem> get favoriteNotes => _sortNotes(
        _allNotes
            .where((n) =>
                !n.isDeletedPermanently &&
                !n.isTrashed &&
                !n.isArchived &&
                n.isFavorite)
            .toList(),
      );

  List<NoteItem> get checklistNotes => _sortNotes(
        _allNotes
            .where((n) =>
                !n.isDeletedPermanently &&
                !n.isTrashed &&
                !n.isArchived &&
                n.isChecklist)
            .toList(),
      );

  List<NoteItem> get archivedNotes => _sortNotes(
        _allNotes
            .where((n) => !n.isDeletedPermanently && !n.isTrashed && n.isArchived)
            .toList(),
      );

  List<NoteItem> get trashedNotes => _sortNotes(
        _allNotes
            .where((n) => !n.isDeletedPermanently && n.isTrashed)
            .toList(),
      );

  List<String> get allTags {
    final set = <String>{};
    for (final n in activeNotes) {
      set.addAll(n.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<NoteItem> _sortNotes(List<NoteItem> list) {
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await _prefsProvider();
    final savedFolders = prefs.getStringList(_prefsFoldersKey);
    if (savedFolders != null && savedFolders.isNotEmpty) {
      _folders = savedFolders;
    }

    String? rawJson;
    final file = await _resolveStorageFile();
    if (file != null && await file.exists()) {
      try {
        rawJson = await file.readAsString();
      } catch (_) {}
    }
    rawJson ??= prefs.getString(_prefsNotesKey);

    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          _allNotes = decoded
              .whereType<Map>()
              .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        } else if (decoded is Map && decoded['notes'] is List) {
          _allNotes = (decoded['notes'] as List)
              .whereType<Map>()
              .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }

    final seeded = prefs.getBool(_prefsSeededKey) ?? false;
    if (!seeded && _allNotes.isEmpty) {
      final now = DateTime.now().toUtc();
      _allNotes = [
        NoteItem(
          id: 'welcome-note-1',
          title: 'Welcome to Notes For Me',
          content:
              'Your offline-first personal workspace for quick thoughts, checklists, and notebooks.\n\n'
              '• Pin important notes to keep them at the top\n'
              '• Organize with folders and #tags\n'
              '• Enable Biometric App Lock in Security settings\n'
              '• Connect Google Drive to sync across Android & Windows',
          folder: 'Personal',
          tags: const ['welcome', 'tips'],
          color: NoteColor.indigo,
          isChecklist: false,
          checklist: const [],
          isPinned: true,
          isFavorite: true,
          isArchived: false,
          isTrashed: false,
          isLocked: false,
          createdAt: now,
          updatedAt: now,
        ),
        NoteItem(
          id: 'welcome-checklist-2',
          title: 'Daily Setup Checklist',
          content: '',
          folder: 'Personal',
          tags: const ['checklist'],
          color: NoteColor.amber,
          isChecklist: true,
          checklist: const [
            ChecklistItem(id: 'c1', text: 'Create your first notebook note', isDone: true),
            ChecklistItem(id: 'c2', text: 'Try dark or light theme toggle', isDone: false),
            ChecklistItem(id: 'c3', text: 'Sign in with Google Drive to sync', isDone: false),
          ],
          isPinned: false,
          isFavorite: false,
          isArchived: false,
          isTrashed: false,
          isLocked: false,
          createdAt: now.subtract(const Duration(minutes: 5)),
          updatedAt: now.subtract(const Duration(minutes: 5)),
        ),
      ];
      await prefs.setBool(_prefsSeededKey, true);
      await _persist();
    }

    notifyListeners();
  }

  Future<File?> _resolveStorageFile() async {
    final dir = await _directoryProvider();
    if (dir == null) return null;
    final sub = Directory('${dir.path}/notes_for_me');
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return File('${sub.path}/notes.json');
  }

  Future<void> _persist() async {
    final payload = jsonEncode(_allNotes.map((n) => n.toJson()).toList());
    final prefs = await _prefsProvider();
    await prefs.setString(_prefsNotesKey, payload);
    await prefs.setStringList(_prefsFoldersKey, _folders);

    final file = await _resolveStorageFile();
    if (file != null) {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(payload);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    }
  }

  String _generateId() =>
      'note_${DateTime.now().microsecondsSinceEpoch}_${_allNotes.length}';

  Future<NoteItem> createNote({
    String title = '',
    String content = '',
    String folder = 'Personal',
    List<String> tags = const [],
    NoteColor color = NoteColor.neutral,
    bool isChecklist = false,
    List<ChecklistItem> checklist = const [],
    bool isPinned = false,
    bool isFavorite = false,
    bool isLocked = false,
  }) async {
    await initialize();
    ensureFolderExists(folder);
    final now = DateTime.now().toUtc();
    final item = NoteItem(
      id: _generateId(),
      title: title,
      content: content,
      folder: folder,
      tags: tags,
      color: color,
      isChecklist: isChecklist,
      checklist: checklist,
      isPinned: isPinned,
      isFavorite: isFavorite,
      isArchived: false,
      isTrashed: false,
      isLocked: isLocked,
      createdAt: now,
      updatedAt: now,
    );
    _allNotes.add(item);
    await _persist();
    notifyListeners();
    return item;
  }

  Future<void> saveNote(NoteItem updated) async {
    await initialize();
    ensureFolderExists(updated.folder);
    final stamped = updated.copyWith(updatedAt: DateTime.now().toUtc());
    final idx = _allNotes.indexWhere((n) => n.id == updated.id);
    if (idx == -1) {
      _allNotes.add(stamped);
    } else {
      _allNotes[idx] = stamped;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    final note = _findById(id);
    if (note == null) return;
    await saveNote(note.copyWith(isPinned: !note.isPinned));
  }

  Future<void> toggleFavorite(String id) async {
    final note = _findById(id);
    if (note == null) return;
    await saveNote(note.copyWith(isFavorite: !note.isFavorite));
  }

  Future<void> toggleArchive(String id) async {
    final note = _findById(id);
    if (note == null) return;
    await saveNote(note.copyWith(
      isArchived: !note.isArchived,
      isPinned: false,
    ));
  }

  Future<void> moveToTrash(String id) async {
    final note = _findById(id);
    if (note == null) return;
    await saveNote(note.copyWith(
      isTrashed: true,
      isPinned: false,
    ));
  }

  Future<void> restoreFromTrash(String id) async {
    final note = _findById(id);
    if (note == null) return;
    await saveNote(note.copyWith(isTrashed: false));
  }

  Future<void> deletePermanently(String id) async {
    final note = _findById(id);
    if (note == null) return;
    final now = DateTime.now().toUtc();
    await saveNote(note.copyWith(
      isTrashed: true,
      deletedAt: now,
      updatedAt: now,
    ));
  }

  Future<void> emptyTrash() async {
    await initialize();
    final now = DateTime.now().toUtc();
    for (var i = 0; i < _allNotes.length; i++) {
      if (_allNotes[i].isTrashed && !_allNotes[i].isDeletedPermanently) {
        _allNotes[i] = _allNotes[i].copyWith(
          deletedAt: now,
          updatedAt: now,
        );
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> toggleChecklistItem(String noteId, String itemId) async {
    final note = _findById(noteId);
    if (note == null) return;
    final updatedItems = note.checklist
        .map((c) => c.id == itemId ? c.copyWith(isDone: !c.isDone) : c)
        .toList();
    await saveNote(note.copyWith(checklist: updatedItems));
  }

  Future<NoteItem?> duplicateNote(String id) async {
    final note = _findById(id);
    if (note == null) return null;
    return createNote(
      title: note.title.isEmpty ? 'Copy' : '${note.title} (Copy)',
      content: note.content,
      folder: note.folder,
      tags: List<String>.from(note.tags),
      color: note.color,
      isChecklist: note.isChecklist,
      checklist: note.checklist.map((e) => e.copyWith()).toList(),
    );
  }

  void ensureFolderExists(String folder) {
    final clean = folder.trim();
    if (clean.isEmpty) return;
    if (!_folders.contains(clean)) {
      _folders = [..._folders, clean];
    }
  }

  Future<void> addFolder(String folder) async {
    await initialize();
    final clean = folder.trim();
    if (clean.isEmpty || _folders.contains(clean)) return;
    _folders = [..._folders, clean];
    await _persist();
    notifyListeners();
  }

  String exportBackupJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'notes_for_me',
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'folders': _folders,
      'notes': _allNotes.map((n) => n.toJson()).toList(),
    });
  }

  Future<int> mergeBackupJson(String rawJson) async {
    await initialize();
    final decoded = jsonDecode(rawJson);
    final List<dynamic> remoteList;
    if (decoded is Map && decoded['notes'] is List) {
      remoteList = decoded['notes'] as List;
      if (decoded['folders'] is List) {
        for (final f in decoded['folders'] as List) {
          ensureFolderExists(f.toString());
        }
      }
    } else if (decoded is List) {
      remoteList = decoded;
    } else {
      throw const FormatException('Invalid Notes For Me backup JSON format.');
    }

    var mergedCount = 0;
    for (final raw in remoteList) {
      if (raw is! Map) continue;
      final remote = NoteItem.fromJson(Map<String, dynamic>.from(raw));
      if (remote.id.isEmpty) continue;
      ensureFolderExists(remote.folder);
      final localIdx = _allNotes.indexWhere((n) => n.id == remote.id);
      if (localIdx == -1) {
        _allNotes.add(remote);
        mergedCount++;
      } else if (remote.updatedAt.isAfter(_allNotes[localIdx].updatedAt)) {
        _allNotes[localIdx] = remote;
        mergedCount++;
      }
    }
    await _persist();
    notifyListeners();
    return mergedCount;
  }

  NoteItem? _findById(String id) {
    for (final n in _allNotes) {
      if (n.id == id) return n;
    }
    return null;
  }
}
