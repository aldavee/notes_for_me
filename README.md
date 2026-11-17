# Notes For Me (Android & Desktop)

Offline-first personal notes, interactive checklists, notebooks, biometric vault, and Google Drive sync built with Flutter for **Android**, **Windows**, and **Linux**.

## Features

- **Offline-First Notes & Checklists**: Create, edit, pin, favorite, archive, trash, and restore notes with automatic local persistence.
- **Notebooks, Tags & Color Accents**: Group notes by folder (`Personal`, `Work`, `Ideas`, `Study`, or custom folders), `#tags`, and Material 3 color tints.
- **Biometric App Lock & Locked Notes**: Optional fingerprint / Face Unlock / Windows Hello / device PIN protection (`local_auth`).
- **Google Drive Sync & JSON Backup**: Back up and merge notes across devices via Google Drive (`Notes For Me/notes_for_me_backup.json`) or clipboard JSON export/import.
- **In-App Version Checker & Google Drive Updater**: Checks Google Drive `latest_release.json`, `https://notes.aldavelabs.com`, or GitHub Releases and installs signed split-ABI APKs on Android.
- **Adaptive Desktop & Mobile UI**: `NavigationRail` sidebar on wide screens, Light/Dark/System themes, and keyboard shortcuts (`Ctrl+N`, `Ctrl+F`, `Ctrl+S`, `F5`).

## Android Configuration

- **Application ID**: `com.aldavelabs.notes_for_me`
- **Release Portal**: `https://notes.aldavelabs.com`

## CI/CD Secrets & Variables (GitHub Actions → `production` environment)

Same Google Drive & Android signing pattern as `pocket_shelf`:

- `GDRIVE_REFRESH_TOKEN`, `GDRIVE_CLIENT_ID`, `GDRIVE_CLIENT_SECRET` (or `GDRIVE_SERVICE_ACCOUNT_JSON`)
- `GDRIVE_RELEASE_FOLDER_ID`, `GDRIVE_MANIFEST_FILE_ID`, `GDRIVE_API_KEY`, `GDRIVE_PUBLIC_RELEASES`
- `GOOGLE_DESKTOP_CLIENT_ID` (defaults to `702325277685-1dg53pr10l0n8tc2ftug9agqfv840h9h.apps.googleusercontent.com` in workflow & `AuthConfig`), `GOOGLE_DESKTOP_CLIENT_SECRET` (required for Desktop Google Drive OAuth token exchange)
- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
