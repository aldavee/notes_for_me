import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:notes_for_me/core/config/auth_config.dart';
import 'package:notes_for_me/features/drive_sync/data/desktop_oauth_client.dart';

class _BearerAuthClient extends http.BaseClient {
  _BearerAuthClient(this._token, [http.Client? inner])
      : _inner = inner ?? http.Client();

  final String _token;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}

class DriveAccountProfile {
  final String email;
  final String displayName;

  const DriveAccountProfile({
    required this.email,
    required this.displayName,
  });
}

class NotesDriveSyncService extends ChangeNotifier {
  NotesDriveSyncService._();
  static final NotesDriveSyncService instance = NotesDriveSyncService._();

  static const List<String> _scopes = <String>[
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveReadonlyScope,
    'email',
    'profile',
  ];

  static const String backupFolderName = 'Notes For Me';
  static const String backupFileName = 'notes_for_me_backup.json';

  final DesktopOAuthClient _desktopOAuth = DesktopOAuthClient();
  GoogleSignInAccount? _androidUser;
  DriveAccountProfile? _profile;
  bool _initialized = false;
  DateTime? _lastSyncedAt;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get isSignedIn => _profile != null;
  DriveAccountProfile? get profile => _profile;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (_isDesktop) {
      await _desktopOAuth.loadSavedSession();
      try {
        final token = await _desktopOAuth.getValidAccessToken();
        if (token != null) {
          await _fetchUserProfileFromToken(token);
        }
      } catch (_) {}
      notifyListeners();
      return;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await GoogleSignIn.instance.initialize(
          serverClientId: AuthConfig.serverClientId.isNotEmpty
              ? AuthConfig.serverClientId
              : null,
        );
        final account = await GoogleSignIn.instance
            .attemptLightweightAuthentication();
        if (account != null) {
          _androidUser = account;
          _profile = DriveAccountProfile(
            email: account.email,
            displayName: account.displayName ?? account.email,
          );
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  Future<bool> signIn() async {
    await initialize();
    if (_isDesktop) {
      final token = await _desktopOAuth.signInInteractive(scopes: _scopes);
      await _fetchUserProfileFromToken(token);
      notifyListeners();
      return _profile != null;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: _scopes,
      );
      _androidUser = account;
      _profile = DriveAccountProfile(
        email: account.email,
        displayName: account.displayName ?? account.email,
      );
      notifyListeners();
      return true;
    }

    throw UnsupportedError('Google Drive sign-in is not supported on this platform.');
  }

  Future<void> signOut() async {
    if (_isDesktop) {
      await _desktopOAuth.clearSession();
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
      _androidUser = null;
    }
    _profile = null;
    notifyListeners();
  }

  Future<void> _fetchUserProfileFromToken(String token) async {
    try {
      final resp = await http
          .get(
            Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final email = (json['email'] ?? '').toString().trim();
        final name = (json['name'] ?? email).toString().trim();
        if (email.isNotEmpty) {
          _profile = DriveAccountProfile(email: email, displayName: name);
        }
      }
    } catch (_) {
      _profile ??= const DriveAccountProfile(
        email: 'Google Account',
        displayName: 'Google Account',
      );
    }
  }

  Future<Map<String, String>?> getAuthHeaders() async {
    if (_isDesktop) {
      final token = await _desktopOAuth.getValidAccessToken();
      if (token == null) return null;
      return {'Authorization': 'Bearer $token'};
    }
    final user = _androidUser;
    if (user == null) return null;
    final auth = await user.authorizationClient.authorizationForScopes(_scopes);
    final token = auth?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  Future<drive.DriveApi?> _getDriveApi() async {
    if (_isDesktop) {
      final token = await _desktopOAuth.getValidAccessToken();
      if (token == null) return null;
      return drive.DriveApi(_BearerAuthClient(token));
    }
    final user = _androidUser;
    if (user == null) return null;
    var auth = await user.authorizationClient.authorizationForScopes(_scopes);
    auth ??= await user.authorizationClient.authorizeScopes(_scopes);
    return drive.DriveApi(auth.authClient(scopes: _scopes));
  }

  Future<String> _ensureBackupFolderId(drive.DriveApi api) async {
    const query =
        "name = '$backupFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final list = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final existing = list.files;
    if (existing != null && existing.isNotEmpty && existing.first.id != null) {
      return existing.first.id!;
    }
    final folder = drive.File()
      ..name = backupFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(folder, $fields: 'id');
    return created.id!;
  }

  Future<String?> downloadBackupJson() async {
    final api = await _getDriveApi();
    if (api == null) return null;
    final folderId = await _ensureBackupFolderId(api);
    final list = await api.files.list(
      q: "name = '$backupFileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name,modifiedTime)',
    );
    final files = list.files;
    if (files == null || files.isEmpty || files.first.id == null) {
      return null;
    }
    final media = await api.files.get(
      files.first.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<void> uploadBackupJson(String jsonContent) async {
    final api = await _getDriveApi();
    if (api == null) {
      throw StateError('Not signed in to Google Drive.');
    }
    final folderId = await _ensureBackupFolderId(api);
    final list = await api.files.list(
      q: "name = '$backupFileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final bytes = utf8.encode(jsonContent);
    final media = drive.Media(Stream.value(bytes), bytes.length);

    final existing = list.files;
    if (existing != null && existing.isNotEmpty && existing.first.id != null) {
      await api.files.update(
        drive.File()..name = backupFileName,
        existing.first.id!,
        uploadMedia: media,
      );
    } else {
      await api.files.create(
        drive.File()
          ..name = backupFileName
          ..mimeType = 'application/json'
          ..parents = [folderId],
        uploadMedia: media,
      );
    }
    _lastSyncedAt = DateTime.now();
    notifyListeners();
  }

  Future<String?> readReleaseManifestText({
    String? manifestFileId,
    String? folderId,
  }) async {
    final api = await _getDriveApi();
    if (api == null) return null;
    try {
      String? targetId = manifestFileId?.trim();
      if ((targetId == null || targetId.isEmpty) &&
          folderId != null &&
          folderId.trim().isNotEmpty) {
        final list = await api.files.list(
          q: "name = 'latest_release.json' and '${folderId.trim()}' in parents and trashed = false",
          $fields: 'files(id)',
        );
        targetId = list.files?.firstOrNull?.id;
      }
      if (targetId == null || targetId.isEmpty) return null;
      final media = await api.files.get(
        targetId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } on SocketException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
