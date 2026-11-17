import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:notes_for_me/core/presentation/widgets/app_snackbar.dart';
import 'package:notes_for_me/features/notes/data/notes_repository.dart';
import 'package:notes_for_me/features/notes/domain/entities/note_item.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    this.initialNote,
    this.initialChecklist = false,
    this.defaultFolder = 'Personal',
    super.key,
  });

  final NoteItem? initialNote;
  final bool initialChecklist;
  final String defaultFolder;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final NotesRepository _repo = NotesRepository.instance;
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagController;
  late TextEditingController _newCheckItemController;

  NoteItem? _existing;
  late String _folder;
  late NoteColor _color;
  late bool _isChecklist;
  late List<ChecklistItem> _checklist;
  late List<String> _tags;
  late bool _isPinned;
  late bool _isFavorite;
  late bool _isLocked;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final n = widget.initialNote;
    _existing = n;
    _titleController = TextEditingController(text: n?.title ?? '');
    _contentController = TextEditingController(text: n?.content ?? '');
    _tagController = TextEditingController();
    _newCheckItemController = TextEditingController();

    _folder = n?.folder ?? widget.defaultFolder;
    _color = n?.color ?? NoteColor.neutral;
    _isChecklist = n?.isChecklist ?? widget.initialChecklist;
    _checklist = n != null
        ? n.checklist.map((e) => e.copyWith()).toList()
        : <ChecklistItem>[];
    _tags = n != null ? List<String>.from(n.tags) : <String>[];
    _isPinned = n?.isPinned ?? false;
    _isFavorite = n?.isFavorite ?? false;
    _isLocked = n?.isLocked ?? false;

    _titleController.addListener(_markDirty);
    _contentController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _newCheckItemController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    } else {
      setState(() {});
    }
  }

  bool get _hasContent =>
      _titleController.text.trim().isNotEmpty ||
      _contentController.text.trim().isNotEmpty ||
      _checklist.isNotEmpty;

  Future<void> _save({bool showToast = false}) async {
    if (!_hasContent && _existing == null) return;

    final title = _titleController.text.trim();
    final content = _contentController.text;

    if (_existing == null) {
      _existing = await _repo.createNote(
        title: title,
        content: content,
        folder: _folder,
        tags: _tags,
        color: _color,
        isChecklist: _isChecklist,
        checklist: _checklist,
        isPinned: _isPinned,
        isFavorite: _isFavorite,
        isLocked: _isLocked,
      );
    } else {
      final updated = _existing!.copyWith(
        title: title,
        content: content,
        folder: _folder,
        tags: _tags,
        color: _color,
        isChecklist: _isChecklist,
        checklist: _checklist,
        isPinned: _isPinned,
        isFavorite: _isFavorite,
        isLocked: _isLocked,
      );
      await _repo.saveNote(updated);
      _existing = updated;
    }
    _dirty = false;
    if (mounted) {
      setState(() {});
      if (showToast) {
        AppSnackBar.show(context, 'Note saved', icon: Icons.check_rounded);
      }
    }
  }

  void _addChecklistItem() {
    final text = _newCheckItemController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklist.add(
        ChecklistItem(
          id: 'chk_${DateTime.now().microsecondsSinceEpoch}',
          text: text,
        ),
      );
      _newCheckItemController.clear();
      _dirty = true;
    });
  }

  void _addTag(String raw) {
    final clean = raw.trim().replaceAll('#', '');
    if (clean.isEmpty || _tags.contains(clean)) return;
    setState(() {
      _tags.add(clean);
      _tagController.clear();
      _dirty = true;
    });
  }

  void _toggleMode() {
    setState(() {
      if (!_isChecklist) {
        final lines = _contentController.text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isNotEmpty && _checklist.isEmpty) {
          _checklist = lines
              .asMap()
              .entries
              .map(
                (e) => ChecklistItem(
                  id: 'chk_${DateTime.now().microsecondsSinceEpoch}_${e.key}',
                  text: e.value.replaceFirst(RegExp(r'^[-*•]\s*'), ''),
                ),
              )
              .toList();
        }
        _isChecklist = true;
      } else {
        if (_checklist.isNotEmpty && _contentController.text.trim().isEmpty) {
          _contentController.text =
              _checklist.map((e) => '${e.isDone ? '[x]' : '[ ]'} ${e.text}').join('\n');
        }
        _isChecklist = false;
      }
      _dirty = true;
    });
  }

  Future<void> _copyMarkdown() async {
    await _save();
    final note = _existing;
    if (note == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: note.toMarkdown()));
    if (mounted) {
      AppSnackBar.show(
        context,
        'Copied as Markdown',
        icon: Icons.copy_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = _color == NoteColor.neutral
        ? theme.scaffoldBackgroundColor
        : _color.surfaceFor(theme.brightness);
    final words = _isChecklist
        ? _checklist
            .map((e) => e.text)
            .join(' ')
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .length
        : _contentController.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _save();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            _save(showToast: true);
          },
        },
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () async {
                await _save();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            actions: [
              IconButton(
                tooltip: _isPinned ? 'Unpin' : 'Pin note',
                icon: Icon(
                  _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: _isPinned ? cs.primary : null,
                ),
                onPressed: () => setState(() {
                  _isPinned = !_isPinned;
                  _dirty = true;
                }),
              ),
              IconButton(
                tooltip: _isFavorite ? 'Remove favorite' : 'Favorite',
                icon: Icon(
                  _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: _isFavorite ? Colors.amber.shade700 : null,
                ),
                onPressed: () => setState(() {
                  _isFavorite = !_isFavorite;
                  _dirty = true;
                }),
              ),
              IconButton(
                tooltip: _isChecklist ? 'Switch to text note' : 'Switch to checklist',
                icon: Icon(
                  _isChecklist
                      ? Icons.notes_rounded
                      : Icons.check_box_outlined,
                ),
                onPressed: _toggleMode,
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'save':
                      await _save(showToast: true);
                      break;
                    case 'lock':
                      setState(() {
                        _isLocked = !_isLocked;
                        _dirty = true;
                      });
                      break;
                    case 'markdown':
                      await _copyMarkdown();
                      break;
                    case 'trash':
                      if (_existing != null) {
                        await _repo.moveToTrash(_existing!.id);
                      }
                      if (context.mounted) Navigator.of(context).pop();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'save',
                    child: ListTile(
                      leading: Icon(Icons.save_rounded),
                      title: Text('Save (Ctrl+S)'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'lock',
                    child: ListTile(
                      leading: Icon(
                        _isLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                      ),
                      title: Text(_isLocked ? 'Unlock note' : 'Lock note'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'markdown',
                    child: ListTile(
                      leading: Icon(Icons.copy_rounded),
                      title: Text('Copy as Markdown'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (_existing != null)
                    const PopupMenuItem(
                      value: 'trash',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Move to Trash'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DropdownButtonHideUnderline(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: DropdownButton<String>(
                                    value: _repo.folders.contains(_folder)
                                        ? _folder
                                        : _repo.folders.first,
                                    isDense: true,
                                    items: _repo.folders
                                        .map((f) => DropdownMenuItem(
                                              value: f,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.folder_outlined,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(f),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _folder = val;
                                          _dirty = true;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                              if (_isLocked)
                                Chip(
                                  avatar: Icon(
                                    Icons.lock_rounded,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                  label: const Text('Locked'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ...NoteColor.values.map((c) {
                                final selected = c == _color;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => setState(() {
                                    _color = c;
                                    _dirty = true;
                                  }),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: c.accent.withValues(alpha: 0.25),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selected ? c.accent : Colors.transparent,
                                        width: 2.5,
                                      ),
                                    ),
                                    child: selected
                                        ? Icon(Icons.check, size: 14, color: c.accent)
                                        : null,
                                  ),
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _titleController,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Note title...',
                              border: InputBorder.none,
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            maxLines: null,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ..._tags.map(
                                (tag) => InputChip(
                                  label: Text('#$tag'),
                                  visualDensity: VisualDensity.compact,
                                  onDeleted: () => setState(() {
                                    _tags.remove(tag);
                                    _dirty = true;
                                  }),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _tagController,
                                  decoration: const InputDecoration(
                                    hintText: '+ add tag',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: _addTag,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          if (_isChecklist) ...[
                            ..._checklist.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final item = entry.value;
                              return Row(
                                children: [
                                  Checkbox(
                                    value: item.isDone,
                                    onChanged: (val) => setState(() {
                                      _checklist[idx] =
                                          item.copyWith(isDone: val ?? false);
                                      _dirty = true;
                                    }),
                                  ),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: item.text,
                                      style: TextStyle(
                                        decoration: item.isDone
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: item.isDone
                                            ? cs.onSurfaceVariant
                                            : null,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                      onChanged: (txt) {
                                        _checklist[idx] = item.copyWith(text: txt);
                                        _dirty = true;
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () => setState(() {
                                      _checklist.removeAt(idx);
                                      _dirty = true;
                                    }),
                                  ),
                                ],
                              );
                            }),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const SizedBox(width: 12),
                                const Icon(Icons.add_rounded, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _newCheckItemController,
                                    decoration: const InputDecoration(
                                      hintText: 'Add checklist item...',
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (_) => _addChecklistItem(),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _addChecklistItem,
                                  child: const Text('Add'),
                                ),
                              ],
                            ),
                          ] else
                            TextField(
                              controller: _contentController,
                              maxLines: null,
                              minLines: 14,
                              keyboardType: TextInputType.multiline,
                              style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                              decoration: const InputDecoration(
                                hintText: 'Start writing your note...',
                                border: InputBorder.none,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _isChecklist
                                ? '${_checklist.where((e) => e.isDone).length}/${_checklist.length} done'
                                : '$words words',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => _save(showToast: true),
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: Text(_dirty ? 'Save' : 'Saved'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
