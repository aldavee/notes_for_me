import 'package:flutter_test/flutter_test.dart';
import 'package:notes_for_me/features/app_update/data/app_update_service.dart';
import 'package:notes_for_me/features/notes/data/notes_repository.dart';
import 'package:notes_for_me/features/notes/domain/entities/note_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('NotesRepository seeds starter notes and supports CRUD + trash', () async {
    final repo = NotesRepository();
    await repo.initialize();

    expect(repo.activeNotes.length, 2);

    final created = await repo.createNote(
      title: 'Meeting Notes',
      content: 'Discuss Q4 roadmap and milestones',
      folder: 'Work',
      tags: const ['roadmap', 'q4'],
      color: NoteColor.emerald,
    );

    expect(repo.activeNotes.any((n) => n.id == created.id), isTrue);
    expect(created.wordCount, 7);
    expect(created.toMarkdown(), contains('# Meeting Notes'));

    await repo.toggleArchive(created.id);
    expect(repo.archivedNotes.any((n) => n.id == created.id), isTrue);

    await repo.moveToTrash(created.id);
    expect(repo.trashedNotes.any((n) => n.id == created.id), isTrue);

    await repo.restoreFromTrash(created.id);
    expect(repo.trashedNotes.any((n) => n.id == created.id), isFalse);

    await repo.deletePermanently(created.id);
    expect(repo.archivedNotes.any((n) => n.id == created.id), isFalse);
    expect(repo.trashedNotes.any((n) => n.id == created.id), isFalse);
  });

  test('NotesRepository merges backup JSON using latest updatedAt', () async {
    final repo = NotesRepository();
    await repo.initialize();

    final local = await repo.createNote(
      title: 'Sync Target',
      content: 'Old local content',
    );
    final newerTimestamp = local.updatedAt.add(const Duration(minutes: 10));
    final backupJson = '''
    {
      "app": "notes_for_me",
      "folders": ["Personal", "Travel"],
      "notes": [
        {
          "id": "${local.id}",
          "title": "Sync Target Updated",
          "content": "Newer remote content",
          "folder": "Travel",
          "tags": ["sync"],
          "color": "sky",
          "isChecklist": false,
          "checklist": [],
          "isPinned": true,
          "isFavorite": false,
          "isArchived": false,
          "isTrashed": false,
          "isLocked": false,
          "createdAt": "${local.createdAt.toIso8601String()}",
          "updatedAt": "${newerTimestamp.toIso8601String()}"
        }
      ]
    }
    ''';

    final merged = await repo.mergeBackupJson(backupJson);
    expect(merged, 1);
    expect(repo.folders, contains('Travel'));
    final updated = repo.activeNotes.firstWhere((n) => n.id == local.id);
    expect(updated.title, 'Sync Target Updated');
    expect(updated.folder, 'Travel');
    expect(updated.isPinned, isTrue);
  });

  test('AppUpdateService.compareVersions compares semver + build correctly', () {
    expect(AppUpdateService.compareVersions('1.0.0+2', '1.0.0+1'), greaterThan(0));
    expect(AppUpdateService.compareVersions('v1.1.0+1', '1.0.9+9'), greaterThan(0));
    expect(AppUpdateService.compareVersions('1.0.0+5', '1.0.0+5'), 0);
    expect(AppUpdateService.compareVersions('1.0.0+1', '1.0.0+3'), lessThan(0));
  });
}
