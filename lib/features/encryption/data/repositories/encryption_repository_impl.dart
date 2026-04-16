import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/encrypted_file.dart';
import '../../domain/repositories/encryption_repository.dart';
import '../datasources/aes_encryption_service.dart';
import '../datasources/encryption_local_datasource.dart';

/// Binds [AesEncryptionService], [EncryptionLocalDataSource], and the
/// device filesystem to fulfil the [EncryptionRepository] contract.
class EncryptionRepositoryImpl implements EncryptionRepository {
  final AesEncryptionService _encryptionService;
  final EncryptionLocalDataSource _localDataSource;
  final Uuid _uuid;

  EncryptionRepositoryImpl({
    required AesEncryptionService encryptionService,
    required EncryptionLocalDataSource localDataSource,
    Uuid uuid = const Uuid(),
  })  : _encryptionService = encryptionService,
        _localDataSource = localDataSource,
        _uuid = uuid;

  // ── Public API ─────────────────────────────────────────────────────────────

  @override
  Future<EncryptedFile> encryptFile({
    required String filePath,
    required String secretKey,
    String? originalFileName,
  }) async {
    try {
      // Prefer the caller-supplied name (which carries the MIME-derived
      // extension from PlatformFile.extension) over the bare filesystem path,
      // which may lack an extension on Android content URIs.
      final originalName = originalFileName ?? p.basename(filePath);
      final id = _uuid.v4();

      // Use the *original* name (not the content-URI cache stem) to derive
      // the encrypted output filename, so history and disk agree.
      final originalBase = p.basenameWithoutExtension(originalName);
      final encFilename = _buildOutputFilename(
        prefix: 'enc',
        baseName: originalBase,
        extension: '.enc',
        id: id,
      );
      final outputPath = await _resolveOutputPath(
        subfolder: 'encrypted files',
        filename: encFilename,
      );

      await _encryptionService.encryptFile(
        inputPath: filePath,
        outputPath: outputPath,
        base64Key: secretKey,
      );

      final record = EncryptedFile(
        id: id,
        originalName: originalName,
        encryptedPath: outputPath,
        secretKey: secretKey,
        createdAt: DateTime.now().toUtc(),
      );

      await _localDataSource.saveRecord(record);
      return record;
    } on Failure {
      rethrow;
    } catch (e) {
      throw EncryptionFailure('Encryption failed: $e');
    }
  }

  @override
  Future<String> decryptFile({
    required String encryptedFilePath,
    required String secretKey,
  }) async {
    try {
      // Look up the Hive history record to recover the original filename
      // (and therefore its extension). Falls back gracefully when the file
      // was encrypted outside this device / not in history.
      EncryptedFile? historyRecord;
      final allRecords = await _localDataSource.getAllRecords();
      for (final r in allRecords) {
        if (r.encryptedPath == encryptedFilePath) {
          historyRecord = r;
          break;
        }
      }

      final String baseName;
      final String extension;
      if (historyRecord != null) {
        baseName = p.basenameWithoutExtension(historyRecord.originalName);
        extension = p.extension(historyRecord.originalName); // ".jpg" or ""
      } else {
        var stem = p.basenameWithoutExtension(encryptedFilePath);
        if (stem.startsWith('enc_')) stem = stem.substring(4);
        baseName = stem;
        extension = ''; // unknown
      }

      final decFilename = _buildOutputFilename(
        prefix: 'dec',
        baseName: baseName,
        extension: extension,
        id: _uuid.v4(),
      );
      final outputPath = await _resolveOutputPath(
        subfolder: 'decrypted files',
        filename: decFilename,
      );

      await _encryptionService.decryptFile(
        inputPath: encryptedFilePath,
        outputPath: outputPath,
        base64Key: secretKey,
      );

      return outputPath;
    } on Failure {
      rethrow;
    } catch (e) {
      throw EncryptionFailure('Decryption failed: $e');
    }
  }

  @override
  Future<List<EncryptedFile>> getHistory() => _localDataSource.getAllRecords();

  @override
  Future<void> clearHistory() => _localDataSource.clearAll();

  @override
  Future<void> deleteHistoryEntry(String id) =>
      _localDataSource.deleteById(id);

  @override
  String generateKey() => _encryptionService.generateKey();

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Builds a collision-free output filename of the form:
  ///
  ///   `{prefix}_{baseName}_{YYYYMMDD_HHmmss}_{uuidPrefix}{extension}`
  ///
  /// Combining a seconds-resolution timestamp *and* a UUID fragment
  /// guarantees uniqueness even on devices with a low-resolution clock and
  /// on rapid batch operations.
  String _buildOutputFilename({
    required String prefix,
    required String baseName,
    required String extension,
    required String id,
  }) {
    final now = DateTime.now();
    final ts = '${now.year}'
        '${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final shortId = id.replaceAll('-', '').substring(0, 8);
    return '${prefix}_${baseName}_${ts}_$shortId$extension';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Returns `<sharedStorageRoot>/SafeHouse/<subfolder>/<filename>`.
  ///
  /// Uses **public shared storage** on Android so files are visible
  /// in any file-manager app under "Internal storage › SafeHouse":
  ///   - Android  → `/storage/emulated/0/SafeHouse/...`
  ///   - iOS      → `<app sandbox>/Documents/SafeHouse/...`
  ///                (iOS sandbox model means there's no equivalent of
  ///                Android's user-visible shared root)
  ///   - Desktop  → platform-appropriate documents dir
  ///
  /// On Android 11+ this path requires the **MANAGE_EXTERNAL_STORAGE**
  /// permission ("All files access"); the caller is expected to have
  /// already gone through [StoragePermission.ensure] before invoking
  /// encrypt/decrypt. If we get here without permission, [Directory.create]
  /// raises a [FileSystemException] which we surface as a [StorageFailure].
  Future<String> _resolveOutputPath({
    required String subfolder,
    required String filename,
  }) async {
    final Directory root;
    if (Platform.isAndroid) {
      // The canonical primary-storage root on essentially every Android
      // device since 4.2. /sdcard is a symlink to this same path.
      root = Directory('/storage/emulated/0');
    } else {
      root = await getApplicationDocumentsDirectory();
    }

    final dir = Directory(p.join(root.path, 'SafeHouse', subfolder));
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } on FileSystemException catch (e) {
      throw StorageFailure(
        'Could not create output folder "${dir.path}". '
        'Make sure SafeHouse has "All files access" enabled in Settings. '
        '(${e.osError?.message ?? e.message})',
      );
    }
    return p.join(dir.path, filename);
  }
}
