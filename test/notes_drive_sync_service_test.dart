import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_for_me/core/presentation/widgets/app_snackbar.dart';
import 'package:notes_for_me/features/drive_sync/data/notes_drive_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android signIn authorizes Drive scopes without serverClientId',
      () async {
    var initCalls = 0;
    final promptFlags = <bool>[];
    String? clearedToken;

    final mockHttp = MockClient((request) async {
      if (request.url.path.endsWith('/drive/v3/about')) {
        return http.Response(
          jsonEncode({
            'user': {
              'displayName': 'Al Dave',
              'emailAddress': 'djaldave@gmail.com',
            },
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('Not found', 404);
    });

    final service = NotesDriveSyncService.forTest(
      httpClient: mockHttp,
      androidInitFn: () async {
        initCalls++;
      },
      androidAuthorizeFn: (scopes, {required promptIfUnauthorized}) async {
        promptFlags.add(promptIfUnauthorized);
        expect(scopes, contains('https://www.googleapis.com/auth/drive.file'));
        expect(
          scopes,
          contains('https://www.googleapis.com/auth/drive.readonly'),
        );
        if (!promptIfUnauthorized) return null;
        return GoogleSignInClientAuthorization(accessToken: 'android-tok-1');
      },
      androidSignOutFn: (token) async {
        clearedToken = token;
      },
    );

    await service.initialize();
    expect(initCalls, 1);
    expect(service.isSignedIn, isFalse);

    final ok = await service.signIn();
    expect(ok, isTrue);
    expect(initCalls, 1);
    expect(promptFlags, [false, true]);
    expect(service.isSignedIn, isTrue);
    expect(service.profile?.email, 'djaldave@gmail.com');
    expect(service.profile?.displayName, 'Al Dave');

    final headers = await service.getAuthHeaders();
    expect(headers, {'Authorization': 'Bearer android-tok-1'});

    await service.signOut();
    expect(clearedToken, 'android-tok-1');
    expect(service.isSignedIn, isFalse);
    expect(service.profile, isNull);
  });

  test('Android initialize silently restores existing Drive authorization',
      () async {
    final mockHttp = MockClient((request) async {
      if (request.url.path.endsWith('/drive/v3/about')) {
        return http.Response(
          jsonEncode({
            'user': {
              'displayName': 'Saved User',
              'emailAddress': 'saved@gmail.com',
            },
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('Not found', 404);
    });

    final service = NotesDriveSyncService.forTest(
      httpClient: mockHttp,
      androidInitFn: () async {},
      androidAuthorizeFn: (scopes, {required promptIfUnauthorized}) async {
        expect(promptIfUnauthorized, isFalse);
        return GoogleSignInClientAuthorization(accessToken: 'silent-tok-9');
      },
    );

    await service.initialize();
    expect(service.isSignedIn, isTrue);
    expect(service.profile?.email, 'saved@gmail.com');
    expect(service.profile?.displayName, 'Saved User');
  });

  test('AppSnackBar.sanitizeError formats GoogleSignInException cleanly', () {
    const configErr = GoogleSignInException(
      code: GoogleSignInExceptionCode.clientConfigurationError,
      description: 'serverClientId must be provided on Android',
    );
    expect(
      AppSnackBar.sanitizeError(configErr),
      'Google Sign-In client config error (check OAuth SHA-1).',
    );

    const canceledErr = GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
      description: 'Canceled',
    );
    expect(AppSnackBar.sanitizeError(canceledErr), 'Sign-in was canceled.');

    expect(
      AppSnackBar.sanitizeError(
        Exception('SDK reported an exception: 16: Caller canceled'),
      ),
      'Sign-in was canceled.',
    );
  });
}
