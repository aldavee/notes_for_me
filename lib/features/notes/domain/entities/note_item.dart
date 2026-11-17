import 'package:material_ui/material_ui.dart';

enum NoteColor {
  neutral('Default', Color(0xFF64748B), Color(0xFFF8FAFC), Color(0xFF1E293B)),
  amber('Amber', Color(0xFFD97706), Color(0xFFFFFBEB), Color(0xFF2D2212)),
  emerald('Emerald', Color(0xFF059669), Color(0xFFECFDF5), Color(0xFF112922)),
  sky('Sky', Color(0xFF0284C7), Color(0xFFF0F9FF), Color(0xFF102436)),
  indigo('Indigo', Color(0xFF4F46E5), Color(0xFFEEF2FF), Color(0xFF1E1E38)),
  rose('Rose', Color(0xFFE11D48), Color(0xFFFFF1F2), Color(0xFF321620)),
  violet('Violet', Color(0xFF7C3AED), Color(0xFFF5F3FF), Color(0xFF261A38));

  const NoteColor(this.label, this.accent, this.lightTint, this.darkTint);

  final String label;
  final Color accent;
  final Color lightTint;
  final Color darkTint;

  Color surfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkTint : lightTint;

  static NoteColor fromName(String? name) {
    return NoteColor.values.firstWhere(
      (c) => c.name == name,
      orElse: () => NoteColor.neutral,
    );
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.isDone = false,
  });

  final String id;
  final String text;
  final bool isDone;

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? isDone,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isDone': isDone,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: (json['id'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      isDone: json['isDone'] == true,
    );
  }
}

class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    required this.content,
    required this.folder,
    required this.tags,
    required this.color,
    required this.isChecklist,
    required this.checklist,
    required this.isPinned,
    required this.isFavorite,
    required this.isArchived,
    required this.isTrashed,
    required this.isLocked,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String content;
  final String folder;
  final List<String> tags;
  final NoteColor color;
  final bool isChecklist;
  final List<ChecklistItem> checklist;
  final bool isPinned;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrashed;
  final bool isLocked;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeletedPermanently => deletedAt != null;

  int get wordCount {
    final text = isChecklist
        ? checklist.map((e) => e.text).join(' ')
        : '$title $content';
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  int get completedChecklistCount => checklist.where((c) => c.isDone).length;

  NoteItem copyWith({
    String? id,
    String? title,
    String? content,
    String? folder,
    List<String>? tags,
    NoteColor? color,
    bool? isChecklist,
    List<ChecklistItem>? checklist,
    bool? isPinned,
    bool? isFavorite,
    bool? isArchived,
    bool? isTrashed,
    bool? isLocked,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return NoteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      folder: folder ?? this.folder,
      tags: tags ?? this.tags,
      color: color ?? this.color,
      isChecklist: isChecklist ?? this.isChecklist,
      checklist: checklist ?? this.checklist,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  String toMarkdown() {
    final buf = StringBuffer();
    if (title.trim().isNotEmpty) {
      buf.writeln('# ${title.trim()}');
      buf.writeln();
    }
    if (tags.isNotEmpty) {
      buf.writeln(tags.map((t) => '#$t').join(' '));
      buf.writeln();
    }
    if (isChecklist) {
      for (final item in checklist) {
        buf.writeln('- [${item.isDone ? 'x' : ' '}] ${item.text}');
      }
    } else {
      buf.writeln(content.trim());
    }
    return buf.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'folder': folder,
        'tags': tags,
        'color': color.name,
        'isChecklist': isChecklist,
        'checklist': checklist.map((e) => e.toJson()).toList(),
        'isPinned': isPinned,
        'isFavorite': isFavorite,
        'isArchived': isArchived,
        'isTrashed': isTrashed,
        'isLocked': isLocked,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
      };

  factory NoteItem.fromJson(Map<String, dynamic> json) {
    final rawChecklist = json['checklist'];
    final checklist = rawChecklist is List
        ? rawChecklist
            .whereType<Map>()
            .map((e) => ChecklistItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ChecklistItem>[];
    final rawTags = json['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString().trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];
    return NoteItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      folder: (json['folder'] ?? 'Personal').toString().trim().isEmpty
          ? 'Personal'
          : (json['folder'] ?? 'Personal').toString().trim(),
      tags: tags,
      color: NoteColor.fromName(json['color']?.toString()),
      isChecklist: json['isChecklist'] == true,
      checklist: checklist,
      isPinned: json['isPinned'] == true,
      isFavorite: json['isFavorite'] == true,
      isArchived: json['isArchived'] == true,
      isTrashed: json['isTrashed'] == true,
      isLocked: json['isLocked'] == true,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      deletedAt: json['deletedAt'] != null
          ? DateTime.tryParse(json['deletedAt'].toString())
          : null,
    );
  }
}
