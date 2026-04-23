import 'dart:convert';
import 'dart:io';

// Aliased to avoid a name clash with `Key` from `package:flutter/foundation`.
import 'package:encrypt/encrypt.dart' as enc show Key, IV;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../../../core/errors/failures.dart';

/// Stateless AES-256-GCM (AEAD) encryption/decryption service.
///
/// Wire format: `[IV (12 bytes)] || [ciphertext] || [auth tag (16 bytes)]`.
/// Because GCM is authenticated, any tampering with the ciphertext, IV, or
/// tag produces an [InvalidCipherTextException] at decryption — there is
/// no silent "wrong-key-looks-like-success" path that CBC-PKCS7 exhibits.
///
/// Large files are processed in chunks on a background isolate (via
/// [compute]) so the UI never blocks and memory stays bounded regardless
/// of file size.
class AesEncryptionService {
  static const int keyLength = 32; // 256-bit key
  static const int ivLength = 12; // 96-bit IV — GCM standard
  static const int tagLength = 16; // 128-bit auth tag

  /// Generates a cryptographically random 256-bit AES key.
  /// Returns the key as a standard base64 string safe for display/storage.
  String generateKey() {
    final key = enc.Key.fromSecureRandom(keyLength);
    return base64Encode(key.bytes);
  }

  /// Returns `true` when [base64Key] decodes to exactly 32 bytes.
  bool isValidKey(String base64Key) {
    try {
      final bytes = base64Decode(base64Key);
      return bytes.length == keyLength;
    } catch (_) {
      return false;
    }
  }

  /// Encrypts [inputPath] to [outputPath] using AES-256-GCM with [base64Key].
  ///
  /// Runs on a background isolate. Streams the input through a chunked
  /// cipher, so peak memory is O(chunk size) regardless of file size.
  Future<void> encryptFile({
    required String inputPath,
    required String outputPath,
    required String base64Key,
  }) async {
    final keyBytes = _decodeKey(base64Key);

    // Pre-flight: keep custom [Failure] types on the main isolate so we
    // don't rely on cross-isolate error serialization.
    if (!await File(inputPath).exists()) {
      throw const FilePickerFailure('Source file no longer exists.');
    }

    try {
      await compute(
        _encryptEntryPoint,
        _CryptoJob(
          inputPath: inputPath,
          outputPath: outputPath,
          keyBytes: keyBytes,
        ),
      );
    } catch (e) {
      throw EncryptionFailure('Encryption failed: $e');
    }
  }

  /// Decrypts [inputPath] to [outputPath] using AES-256-GCM with [base64Key].
  ///
  /// Throws [EncryptionFailure] if the auth tag fails to verify — the most
  /// common cause is a wrong key, a tampered ciphertext, or a truncated file.
  Future<void> decryptFile({
    required String inputPath,
    required String outputPath,
    required String base64Key,
  }) async {
    final keyBytes = _decodeKey(base64Key);

    final input = File(inputPath);
    if (!await input.exists()) {
      throw const FilePickerFailure('Encrypted file no longer exists.');
    }
    if (await input.length() < ivLength + tagLength) {
      throw const EncryptionFailure(
        'Encrypted data is too short — likely not a SafeHouse file.',
      );
    }

    try {
      await compute(
        _decryptEntryPoint,
        _CryptoJob(
          inputPath: inputPath,
          outputPath: outputPath,
          keyBytes: keyBytes,
        ),
      );
    } catch (_) {
      // A GCM tag-mismatch surfaces as InvalidCipherTextException — we
      // don't expose the raw exception text to avoid leaking internals,
      // and we've already cleaned up the partial output in the isolate.
      throw const EncryptionFailure(
        'Decryption failed — wrong key, tampered, or corrupt file.',
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Uint8List _decodeKey(String base64Key) {
    if (!isValidKey(base64Key)) {
      throw const InvalidKeyFailure();
    }
    return Uint8List.fromList(base64Decode(base64Key));
  }
}

// ── Isolate payload ──────────────────────────────────────────────────────────

/// Serializable job sent to the background isolate via [compute]. Only
/// primitive / transferable types cross the isolate boundary — each isolate
/// opens its own file streams.
class _CryptoJob {
  final String inputPath;
  final String outputPath;
  final Uint8List keyBytes;

  const _CryptoJob({
    required this.inputPath,
    required this.outputPath,
    required this.keyBytes,
  });
}

// ── Top-level isolate entry points ───────────────────────────────────────────
//
// Must be top-level so `compute` can address them from a fresh isolate.

Future<void> _encryptEntryPoint(_CryptoJob job) async {
  final iv = enc.IV.fromSecureRandom(AesEncryptionService.ivLength).bytes;

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(job.keyBytes),
        AesEncryptionService.tagLength * 8,
        iv,
        Uint8List(0),
      ),
    );

  final sink = File(job.outputPath).openWrite();
  try {
    // Prepend IV so the decrypter can recover it without side-metadata.
    sink.add(iv);

    await for (final chunk in File(job.inputPath).openRead()) {
      final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      // GCM buffers up to one partial AES block (< 16 bytes) across calls,
      // so processBytes can emit up to `len + 15` bytes. Allocate 2 blocks
      // of headroom — trivially correct regardless of PointyCastle's
      // internal buffering strategy.
      final out = Uint8List(data.length + 32);
      final n = cipher.processBytes(data, 0, data.length, out, 0);
      if (n > 0) sink.add(Uint8List.sublistView(out, 0, n));
    }

    // Flush any remaining block + write the 16-byte auth tag.
    // Max: bufOff (<16) + tagLength (16) = 32.
    final tail = Uint8List(32);
    final tailLen = cipher.doFinal(tail, 0);
    if (tailLen > 0) sink.add(Uint8List.sublistView(tail, 0, tailLen));

    await sink.flush();
  } finally {
    await sink.close();
  }
}

Future<void> _decryptEntryPoint(_CryptoJob job) async {
  final input = File(job.inputPath);

  // Read the first 12 bytes (IV) so we can init GCM before streaming
  // ciphertext. We use a RandomAccessFile for the IV only, then a regular
  // streaming read for the remainder.
  final ivHandle = await input.open();
  Uint8List iv;
  try {
    iv = await ivHandle.read(AesEncryptionService.ivLength);
  } finally {
    await ivHandle.close();
  }

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(job.keyBytes),
        AesEncryptionService.tagLength * 8,
        iv,
        Uint8List(0),
      ),
    );

  final sink = File(job.outputPath).openWrite();
  try {
    // Stream ciphertext (everything after the IV). GCM's doFinal() will
    // consume the last 16 bytes as the auth tag.
    await for (final chunk in input.openRead(AesEncryptionService.ivLength)) {
      final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      // Decrypt output is bounded by input length (tag bytes are stripped),
      // but GCM still buffers a partial AES block internally. Match the
      // encrypt path's trivially-correct `len + 32` headroom so we don't
      // have to reason about PointyCastle's internal state machine.
      final out = Uint8List(data.length + 32);
      final n = cipher.processBytes(data, 0, data.length, out, 0);
      if (n > 0) sink.add(Uint8List.sublistView(out, 0, n));
    }

    // Flush: at most bufOff (<16) bytes of plaintext remain after tag strip.
    final tail = Uint8List(32);
    final tailLen = cipher.doFinal(tail, 0);
    if (tailLen > 0) sink.add(Uint8List.sublistView(tail, 0, tailLen));

    await sink.flush();
    await sink.close();
  } catch (err) {
    // On any failure (most commonly InvalidCipherTextException from a
    // failed tag check) we delete the partial plaintext so we don't
    // leave a half-written garbage file on disk.
    try {
      await sink.close();
    } catch (_) {
      /* already closed */
    }
    try {
      final partial = File(job.outputPath);
      if (await partial.exists()) await partial.delete();
    } catch (_) {
      /* best effort */
    }
    rethrow;
  }
}
