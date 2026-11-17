import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_for_me/core/config/auth_config.dart';
import 'package:notes_for_me/features/drive_sync/data/desktop_oauth_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AuthConfig defaults desktop client ID to the Desktop OAuth client', () {
    expect(
      AuthConfig.effectiveDesktopClientId,
      AuthConfig.defaultDesktopClientId,
    );
    expect(AuthConfig.effectiveDesktopClientId, isNot(AuthConfig.clientId));
  });

  test('DesktopOAuthClient ignores /favicon.ico and exchanges code with secret',
      () async {
    late Uri launchedAuthUri;
    Map<String, String>? tokenRequestBody;
    int? faviconStatus;
    int? callbackStatus;

    final mockHttp = MockClient((request) async {
      if (request.url.toString() == AuthConfig.tokenUri) {
        tokenRequestBody = Uri.splitQueryString(request.body);
        return http.Response(
          jsonEncode({
            'access_token': 'access-123',
            'refresh_token': 'refresh-456',
            'expires_in': 3600,
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final client = DesktopOAuthClient(
      httpClient: mockHttp,
      clientId: AuthConfig.defaultDesktopClientId,
      clientSecret: 'test-desktop-secret',
      launchUrlFn: (uri) async {
        launchedAuthUri = uri;
        final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
        final state = uri.queryParameters['state']!;

        unawaited(Future<void>(() async {
          final ioClient = HttpClient();
          try {
            final favReq = await ioClient.getUrl(
              redirectUri.replace(path: '/favicon.ico'),
            );
            final favResp = await favReq.close();
            faviconStatus = favResp.statusCode;
            await favResp.drain<void>();

            final cbReq = await ioClient.getUrl(
              redirectUri.replace(
                queryParameters: {'code': 'auth-code-789', 'state': state},
              ),
            );
            final cbResp = await cbReq.close();
            callbackStatus = cbResp.statusCode;
            await cbResp.drain<void>();
          } finally {
            ioClient.close(force: true);
          }
        }));
        return true;
      },
    );

    final token = await client.signInInteractive(scopes: const ['email']);

    expect(faviconStatus, HttpStatus.noContent);
    expect(callbackStatus, HttpStatus.ok);
    expect(token, 'access-123');
    expect(client.hasSession, isTrue);
    expect(
      launchedAuthUri.queryParameters['client_id'],
      AuthConfig.defaultDesktopClientId,
    );
    expect(launchedAuthUri.queryParameters['code_challenge_method'], 'S256');
    expect(
      launchedAuthUri.queryParameters['redirect_uri'],
      startsWith('http://127.0.0.1:'),
    );
    expect(tokenRequestBody?['client_id'], AuthConfig.defaultDesktopClientId);
    expect(tokenRequestBody?['client_secret'], 'test-desktop-secret');
    expect(tokenRequestBody?['code'], 'auth-code-789');
    expect(tokenRequestBody?['code_verifier'], isNotEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DesktopOAuthClient.prefsKey), isNotNull);
  });

  test('DesktopOAuthClient surfaces Google error_description on token failure',
      () async {
    final mockHttp = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': 'invalid_request',
          'error_description': 'client_secret is missing.',
        }),
        400,
      );
    });

    final client = DesktopOAuthClient(
      httpClient: mockHttp,
      clientId: AuthConfig.defaultDesktopClientId,
      launchUrlFn: (uri) async {
        final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
        final state = uri.queryParameters['state']!;
        unawaited(Future<void>(() async {
          final ioClient = HttpClient();
          try {
            final cbReq = await ioClient.getUrl(
              redirectUri.replace(
                queryParameters: {'code': 'auth-code-000', 'state': state},
              ),
            );
            final cbResp = await cbReq.close();
            await cbResp.drain<void>();
          } finally {
            ioClient.close(force: true);
          }
        }));
        return true;
      },
    );

    await expectLater(
      () => client.signInInteractive(scopes: const ['email']),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('client_secret is missing.'),
        ),
      ),
    );
  });

  test('DesktopOAuthClient refreshes expiring token with client_secret',
      () async {
    final expiredMillis = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      DesktopOAuthClient.prefsKey: jsonEncode({
        'accessToken': 'old-token',
        'refreshToken': 'refresh-keep',
        'expiresAtMillis': expiredMillis,
      }),
    });

    Map<String, String>? refreshBody;
    final mockHttp = MockClient((request) async {
      refreshBody = Uri.splitQueryString(request.body);
      return http.Response(
        jsonEncode({
          'access_token': 'fresh-token',
          'expires_in': 3600,
        }),
        200,
      );
    });

    final client = DesktopOAuthClient(
      httpClient: mockHttp,
      clientId: AuthConfig.defaultDesktopClientId,
      clientSecret: 'test-desktop-secret',
    );
    await client.loadSavedSession();

    final token = await client.getValidAccessToken();
    expect(token, 'fresh-token');
    expect(refreshBody?['grant_type'], 'refresh_token');
    expect(refreshBody?['refresh_token'], 'refresh-keep');
    expect(refreshBody?['client_secret'], 'test-desktop-secret');
  });
}
