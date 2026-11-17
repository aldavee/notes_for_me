import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:notes_for_me/core/presentation/navigation/adaptive_page_route.dart';
import 'package:notes_for_me/core/presentation/widgets/adaptive_overlay.dart';
import 'package:notes_for_me/core/presentation/widgets/app_snackbar.dart';
import 'package:notes_for_me/core/theme/theme_service.dart';
import 'package:notes_for_me/features/app_update/presentation/app_version_checker_card.dart';
import 'package:notes_for_me/features/drive_sync/data/notes_drive_sync_service.dart';
import 'package:notes_for_me/features/notes/data/notes_repository.dart';
import 'package:notes_for_me/features/notes/domain/entities/note_item.dart';
import 'package:notes_for_me/features/notes/presentation/pages/note_editor_page.dart';
import 'package:notes_for_me/features/security/data/biometric_service.dart';
import 'package:notes_for_me/features/security/presentation/biometric_lock_gate.dart';

enum _NotesSection {
  all('All Notes', Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded),
  favorites('Favorites', Icons.star_outline_rounded, Icons.star_rounded),
  checklists('Checklists', Icons.check_box_outlined, Icons.check_box_rounded),
  archived('Archive', Icons.archive_outlined, Icons.archive_rounded),
  trash('Trash', Icons.delete_outline_rounded, Icons.delete_rounded);

  const _NotesSection(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final NotesRepository _repo = NotesRepository.instance;
  final NotesDriveSyncService _driveSync = NotesDriveSyncService.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  _NotesSection _section = _NotesSection.all;
  String? _selectedFolder;
  String? _selectedTag;
  bool _isGrid = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChanged);
    _driveSync.addListener(_onChanged);
    _repo.initialize();
    _driveSync.initialize();
  }

  @override
  void dispose() {
    _repo.removeListener(_onChanged);
    _driveSync.removeListener(_onChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<NoteItem> _filteredNotes() {
    var base = switch (_section) {
      _NotesSection.all => _repo.activeNotes,
      _NotesSection.favorites => _repo.favoriteNotes,
      _NotesSection.checklists => _repo.checklistNotes,
      _NotesSection.archived => _repo.archivedNotes,
      _NotesSection.trash => _repo.trashedNotes,
    };

    if (_selectedFolder != null) {
      base = base.where((n) => n.folder == _selectedFolder).toList();
    }
    if (_selectedTag != null) {
      base = base.where((n) => n.tags.contains(_selectedTag)).toList();
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      base = base.where((n) {
        return n.title.toLowerCase().contains(query) ||
            n.content.toLowerCase().contains(query) ||
            n.folder.toLowerCase().contains(query) ||
            n.tags.any((t) => t.toLowerCase().contains(query)) ||
            n.checklist.any((c) => c.text.toLowerCase().contains(query));
      }).toList();
    }
    return base;
  }

  Future<void> _openEditor({NoteItem? note, bool isChecklist = false}) async {
    if (note != null && note.isLocked && BiometricService.instance.isSupported) {
      final auth = await BiometricService.instance.authenticate(
        reason: 'Authenticate to open locked note',
      );
      if (!auth.success) {
        if (mounted) {
          AppSnackBar.show(
            context,
            auth.errorMessage ?? 'Authentication required',
            backgroundColor: Theme.of(context).colorScheme.error,
          );
        }
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      adaptivePageRoute(
        context,
        builder: (_) => NoteEditorPage(
          initialNote: note,
          initialChecklist: isChecklist,
          defaultFolder: _selectedFolder ?? 'Personal',
        ),
      ),
    );
  }

  Future<void> _syncWithDrive() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      if (!_driveSync.isSignedIn) {
        final ok = await _driveSync.signIn();
        if (!ok) return;
      }
      final remoteJson = await _driveSync.downloadBackupJson();
      var merged = 0;
      if (remoteJson != null && remoteJson.trim().isNotEmpty) {
        merged = await _repo.mergeBackupJson(remoteJson);
      }
      await _driveSync.uploadBackupJson(_repo.exportBackupJson());
      if (mounted) {
        AppSnackBar.show(
          context,
          merged > 0
              ? 'Synced with Google Drive ($merged updated)'
              : 'Notes backed up to Google Drive',
          icon: Icons.cloud_done_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          AppSnackBar.sanitizeError(e),
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Notebook Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'e.g. Journal, Recipes, Projects',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await _repo.addFolder(name.trim());
      setState(() => _selectedFolder = name.trim());
    }
  }

  Future<void> _showBackupSheet() async {
    final jsonCtrl = TextEditingController();
    await showAdaptiveDialogOrSheet<void>(
      context: context,
      maxWidth: 540,
      desktopTitle: 'Backup, Google Drive & Updates',
      desktopIcon: Icons.cloud_sync_rounded,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Icon(
                    _driveSync.isSignedIn
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_outlined,
                  ),
                ),
                title: Text(
                  _driveSync.isSignedIn
                      ? _driveSync.profile?.displayName ?? 'Google Account'
                      : 'Google Drive Sync',
                ),
                subtitle: Text(
                  _driveSync.isSignedIn
                      ? _driveSync.profile?.email ?? 'Connected'
                      : 'Back up & merge notes via Google Drive',
                ),
                trailing: _driveSync.isSignedIn
                    ? TextButton(
                        onPressed: () async {
                          await _driveSync.signOut();
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: const Text('Sign out'),
                      )
                    : FilledButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _syncWithDrive();
                        },
                        child: const Text('Connect'),
                      ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _repo.exportBackupJson()),
                      );
                      if (ctx.mounted) {
                        AppSnackBar.show(
                          ctx,
                          'JSON backup copied to clipboard',
                          icon: Icons.copy_rounded,
                        );
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Copy JSON Backup'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _syncWithDrive();
                    },
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Sync Drive Now'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: jsonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Restore / Merge from JSON Backup',
                  hintText: 'Paste exported Notes For Me JSON here...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    try {
                      final count = await _repo.mergeBackupJson(jsonCtrl.text);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (mounted) {
                        AppSnackBar.show(
                          context,
                          'Merged $count note(s) from backup',
                          icon: Icons.check_circle_outline,
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        AppSnackBar.show(
                          ctx,
                          AppSnackBar.sanitizeError(e),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                        );
                      }
                    }
                  },
                  child: const Text('Import & Merge'),
                ),
              ),
              const Divider(height: 28),
              const AppVersionCheckerCard(autoCheckOnInit: true),
            ],
          ),
        ),
      ),
    );
    jsonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDesktop = isDesktopLayoutContext(context);
    final notes = _filteredNotes();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _openEditor(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f5): _syncWithDrive,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: isDesktop ? 20 : 8,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: cs.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Notes For Me',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: _isGrid ? 'List view' : 'Grid view',
                icon: Icon(
                  _isGrid
                      ? Icons.view_agenda_outlined
                      : Icons.grid_view_rounded,
                ),
                onPressed: () => setState(() => _isGrid = !_isGrid),
              ),
              IconButton(
                tooltip: 'Sync with Google Drive (F5)',
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _driveSync.isSignedIn
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_sync_outlined,
                      ),
                onPressed: _isSyncing ? null : _syncWithDrive,
              ),
              IconButton(
                tooltip: 'Theme: ${ThemeService.instance.modeLabel}',
                icon: Icon(ThemeService.instance.modeIcon),
                onPressed: () => ThemeService.instance.cycleThemeMode(),
              ),
              IconButton(
                tooltip: 'Security & App Lock',
                icon: const Icon(Icons.shield_outlined),
                onPressed: () => BiometricLockGate.showSettingsSheet(context),
              ),
              IconButton(
                tooltip: 'Backup & Updates',
                icon: const Icon(Icons.tune_rounded),
                onPressed: _showBackupSheet,
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  selectedIndex: _section.index,
                  extended: MediaQuery.sizeOf(context).width >= 1100,
                  onDestinationSelected: (idx) {
                    setState(() => _section = _NotesSection.values[idx]);
                  },
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FloatingActionButton.extended(
                      heroTag: 'desktop_new_note',
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New Note'),
                    ),
                  ),
                  destinations: _NotesSection.values
                      .map(
                        (s) => NavigationRailDestination(
                          icon: Icon(s.icon),
                          selectedIcon: Icon(s.selectedIcon),
                          label: Text(s.label),
                        ),
                      )
                      .toList(),
                ),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search notes, #tags, folders...',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.45),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_section == _NotesSection.trash && notes.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: _repo.emptyTrash,
                              icon: const Icon(Icons.delete_forever_rounded, size: 18),
                              label: const Text('Empty Trash'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: const Text('All Folders'),
                              selected: _selectedFolder == null,
                              onSelected: (_) =>
                                  setState(() => _selectedFolder = null),
                            ),
                          ),
                          ..._repo.folders.map(
                            (folder) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(folder),
                                selected: _selectedFolder == folder,
                                onSelected: (sel) => setState(
                                  () => _selectedFolder = sel ? folder : null,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
                              label: const Text('Folder'),
                              onPressed: _showCreateFolderDialog,
                            ),
                          ),
                          ..._repo.allTags.map(
                            (tag) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text('#$tag'),
                                selected: _selectedTag == tag,
                                onSelected: (sel) => setState(
                                  () => _selectedTag = sel ? tag : null,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: notes.isEmpty
                          ? _EmptyNotesState(
                              section: _section,
                              onCreate: () => _openEditor(
                                isChecklist: _section == _NotesSection.checklists,
                              ),
                            )
                          : _isGrid
                              ? GridView.builder(
                                  padding: const EdgeInsets.all(16),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 340,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 1.05,
                                  ),
                                  itemCount: notes.length,
                                  itemBuilder: (ctx, i) => _NoteCard(
                                    note: notes[i],
                                    onTap: () => _openEditor(note: notes[i]),
                                    onTogglePin: () => _repo.togglePin(notes[i].id),
                                    onToggleArchive: () =>
                                        _repo.toggleArchive(notes[i].id),
                                    onTrashOrRestore: () => notes[i].isTrashed
                                        ? _repo.restoreFromTrash(notes[i].id)
                                        : _repo.moveToTrash(notes[i].id),
                                    onDeleteForever: () =>
                                        _repo.deletePermanently(notes[i].id),
                                    onToggleChecklistItem: (itemId) =>
                                        _repo.toggleChecklistItem(
                                      notes[i].id,
                                      itemId,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: notes.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (ctx, i) => _NoteCard(
                                    note: notes[i],
                                    compactList: true,
                                    onTap: () => _openEditor(note: notes[i]),
                                    onTogglePin: () => _repo.togglePin(notes[i].id),
                                    onToggleArchive: () =>
                                        _repo.toggleArchive(notes[i].id),
                                    onTrashOrRestore: () => notes[i].isTrashed
                                        ? _repo.restoreFromTrash(notes[i].id)
                                        : _repo.moveToTrash(notes[i].id),
                                    onDeleteForever: () =>
                                        _repo.deletePermanently(notes[i].id),
                                    onToggleChecklistItem: (itemId) =>
                                        _repo.toggleChecklistItem(
                                      notes[i].id,
                                      itemId,
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _section.index,
                  onDestinationSelected: (idx) {
                    setState(() => _section = _NotesSection.values[idx]);
                  },
                  destinations: _NotesSection.values
                      .map(
                        (s) => NavigationDestination(
                          icon: Icon(s.icon),
                          selectedIcon: Icon(s.selectedIcon),
                          label: s.label,
                        ),
                      )
                      .toList(),
                ),
          floatingActionButton: isDesktop
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'new_checklist_fab',
                      tooltip: 'New checklist',
                      onPressed: () => _openEditor(isChecklist: true),
                      child: const Icon(Icons.check_box_outlined),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      heroTag: 'new_note_fab',
                      tooltip: 'New note',
                      onPressed: () => _openEditor(),
                      child: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleArchive,
    required this.onTrashOrRestore,
    required this.onDeleteForever,
    required this.onToggleChecklistItem,
    this.compactList = false,
  });

  final NoteItem note;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;
  final VoidCallback onTrashOrRestore;
  final VoidCallback onDeleteForever;
  final ValueChanged<String> onToggleChecklistItem;
  final bool compactList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = note.color == NoteColor.neutral
        ? cs.surfaceContainerLow
        : note.color.surfaceFor(theme.brightness);

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: note.color == NoteColor.neutral
                  ? cs.outlineVariant.withValues(alpha: 0.45)
                  : note.color.accent.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: compactList ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Untitled Note' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (note.isLocked)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock_rounded, size: 16, color: cs.primary),
                    ),
                  if (note.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin_rounded, size: 16, color: cs.primary),
                    ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onSelected: (val) {
                      if (val == 'pin') onTogglePin();
                      if (val == 'archive') onToggleArchive();
                      if (val == 'trash') onTrashOrRestore();
                      if (val == 'delete') onDeleteForever();
                    },
                    itemBuilder: (_) => [
                      if (!note.isTrashed) ...[
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(note.isArchived ? 'Unarchive' : 'Archive'),
                        ),
                      ],
                      PopupMenuItem(
                        value: 'trash',
                        child: Text(note.isTrashed ? 'Restore' : 'Move to Trash'),
                      ),
                      if (note.isTrashed)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Forever'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (note.isLocked)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Locked note — tap to unlock',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              else if (note.isChecklist)
                ...note.checklist.take(compactList ? 3 : 4).map(
                      (item) => InkWell(
                        onTap: () => onToggleChecklistItem(item.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                item.isDone
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 16,
                                color: item.isDone
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    decoration: item.isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
              else
                Text(
                  note.content.isEmpty ? 'No additional text' : note.content,
                  maxLines: compactList ? 3 : 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              if (!compactList) const Spacer() else const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      note.folder,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (note.tags.isNotEmpty)
                    Expanded(
                      child: Text(
                        note.tags.map((t) => '#$t').join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (note.isChecklist)
                    Text(
                      '${note.completedChecklistCount}/${note.checklist.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotesState extends StatelessWidget {
  const _EmptyNotesState({
    required this.section,
    required this.onCreate,
  });

  final _NotesSection section;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 52, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No notes in ${section.label}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a note or checklist to capture ideas offline.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (section == _NotesSection.all ||
                section == _NotesSection.checklists) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  section == _NotesSection.checklists
                      ? 'New Checklist'
                      : 'Create Note',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
