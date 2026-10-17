# Encrypted data recovery and storage upgrades

## Why the startup guard exists

`JsonFile` stores its AES-256 key in `flutter_secure_storage` and encrypted
JSON envelopes in app files. If the key is absent or unreadable while an
encrypted envelope remains, `JsonFile.initialize()` fails closed: it does not
create a replacement key, rewrite data, or let services load defaults over the
existing files. The app shows a recovery screen instead of continuing startup.

This protects against a missing key becoming silent data loss; it cannot
reconstruct a key that Android Keystore or secure storage has already deleted.

## Android secure-storage migration bridge

The previous dependency was `flutter_secure_storage` 9.2.4. Its Android
defaults used RSA/PKCS#1 v1.5 key wrapping and AES-CBC data encryption.
Version 10 changes the defaults to RSA-OAEP and AES-GCM. Version 11 removes
the legacy algorithms and its changelog instructs users with pre-v10 data to
upgrade through v10 first.

This app pins `flutter_secure_storage` 10.2.0 and explicitly configures:

```dart
AndroidOptions(
  migrateOnAlgorithmChange: true,
  migrateWithBackup: true,
  resetOnError: false,
)
```

The options preserve the plugin's default preferences name, key prefix, and
Android storage namespace. On an algorithm mismatch, v10.2.0 attempts the
legacy-to-current migration. Its backup-protected non-biometric path copies
encrypted preferences and wrapped keys to `_BACKUP` entries before replacing
them, records per-key `_MIGRATED` progress, and commits each migrated value.
It can resume after an interrupted migration. If migration or a secure-storage
operation fails, `resetOnError: false` makes the plugin report the error
instead of automatically deleting stored entries or keys.

This is safer than v10.0.0: its ordinary migration path deletes the previous
Keystore key and updates algorithm markers before writing all re-encrypted
values; 10.1.0 introduced `migrateWithBackup`, and 10.2.0 includes the
crash-resilient path and fixes. Do not downgrade below 10.2.0 after migration
has started or completed.

## Recovery and release procedure

### Set up recovery before an incident

1. Open Settings and tap the Keramika FOSS title seven times within three
   seconds; enter the existing Developer Corner access code.
2. In Developer Corner, generate a 24-word English BIP-39 phrase. Write it
   down offline, then enter all 24 words to confirm. The phrase is displayed
   only during setup and is never stored by the app.
3. Test the phrase on that screen. A passing test verifies the phrase against
   the current encrypted documents without changing the key or data.
4. Export a new Keramika JSON backup after setting up recovery. The export
   includes `keramika_key_recovery`, an authenticated AES-GCM envelope of the
   existing data-encryption key protected by a PBKDF2-derived phrase key. It
   contains neither the phrase nor a plaintext encryption key. Store the
   backup separately from the phrase.

Changing the phrase re-wraps the same data key. The previous phrase stops
working once the new envelope is saved. Do not change it unless the new phrase
is confirmed and the new backup export is preserved. Existing backups remain
compatible for ordinary import, but backups created before recovery setup do
not contain the recovery envelope and cannot restore a key.

### Recover after losing secure-storage access

1. Do not clear app data or uninstall while the only copy of user data is
   encrypted in app files. Start with an in-place update only after a migration
   build has been validated.
2. On the startup recovery screen, choose the JSON backup that contains
   `keramika_key_recovery`, enter the matching 24-word phrase, and choose
   **Restore encryption key**. The app authenticates the envelope, checks the
   recovered key against existing encrypted documents, and only then writes it
   to secure storage. An invalid phrase or mismatching key does not overwrite
   the stored key or encrypted files.
3. Close and reopen Keramika. If the app was reinstalled, import the same
   backup through Settings after key recovery; restore does not import or
   overwrite application data.
4. Validate recovered datasets before routine use.

If the encrypted documents are gone after reinstall, the backup's recovery
envelope can restore the key, but the backup's ordinary import is still
required to restore the data. A recovery phrase cannot help with a backup made
before the phrase was configured. It cannot recover text absent from the
backup.

If the existing release-signing key is unavailable, a fresh install signed
with a new key requires uninstalling the old signed app first. This removes
its local encrypted data and secure-storage entry; proceed only when the
separate JSON backup is verified. The new key and `android/key.properties`
are local ignored files, not source-controlled configuration. Preserve both
securely: all later in-place APK updates must use the same signing key.

## Limits and current verification

- A successful dependency solve and tests of `JsonFile`'s fail-closed behavior
  do not prove that a particular device's old Keystore key is recoverable.
- `migrateWithBackup` protects the plugin's algorithm migration; it is not a
  substitute for an independent user backup or a device-level recovery test.
- If a prior v11 access already reset or replaced the old secure-storage
  entry, v10.2.0 cannot recreate the original app-level AES key.
- Recovery phrases protect only keys wrapped after the feature is available
  and explicitly configured. Generating a new phrase cannot recover a key
  that was already lost, and the currently preserved 2026-10-17 backup has no
  `keramika_key_recovery` field.
- The preserved 2026-10-17 JSON backup does not contain the later
  `developer_prompt` field; restoring it cannot restore that field's newer
  contents.
- No APK is approved for device installation until the complete primary
  checkout changes are represented, the Android migration path is tested, and
  the backup/restore plan is verified. Device data must remain untouched until
  that point.
