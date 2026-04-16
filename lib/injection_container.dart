import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'features/encryption/data/datasources/aes_encryption_service.dart';
import 'features/encryption/data/datasources/encryption_local_datasource.dart';
import 'features/encryption/data/repositories/encryption_repository_impl.dart';
import 'features/encryption/domain/entities/encrypted_file.dart';
import 'features/encryption/domain/repositories/encryption_repository.dart';
import 'features/encryption/presentation/cubits/encryption_cubit.dart';
import 'features/encryption/presentation/cubits/history_cubit.dart';

/// Global service-locator instance.
/// Access registered objects anywhere via `sl<MyType>()`.
final GetIt sl = GetIt.instance;

/// Key under which the Hive box's AES cipher key is stored in the
/// platform secure storage (Android Keystore / iOS Keychain).
const _kHiveCipherKeyAlias = 'safehouse.hive.cipher.v1';

/// Registers all dependencies in dependency order.
///
/// Called once in [main] before [runApp], after Hive is initialised and
/// adapters are registered.
Future<void> init() async {
  // ── Secure storage ────────────────────────────────────────────────────────
  // Stored on Android via EncryptedSharedPreferences (Keystore-backed) and
  // on iOS via the Keychain. Survives app updates; wiped on uninstall on
  // Android by default.
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Hive cipher key ───────────────────────────────────────────────────────
  // Generate a fresh 256-bit key on first launch and persist it in secure
  // storage; reuse it on subsequent launches.
  final cipherKey = await _readOrCreateHiveCipherKey(secureStorage);

  // ── Hive boxes ────────────────────────────────────────────────────────────
  // Open the box here so it's ready before any datasource is constructed.
  // Using HiveAesCipher means the on-disk file is opaque — secret keys
  // can no longer be read by anyone with filesystem access.
  final encryptedFilesBox = await Hive.openBox<EncryptedFile>(
    EncryptionLocalDataSourceImpl.boxName,
    encryptionCipher: HiveAesCipher(cipherKey),
  );

  // ── Services ──────────────────────────────────────────────────────────────
  sl.registerLazySingleton<AesEncryptionService>(
    () => AesEncryptionService(),
  );

  // ── Data sources ──────────────────────────────────────────────────────────
  sl.registerLazySingleton<EncryptionLocalDataSource>(
    () => EncryptionLocalDataSourceImpl(box: encryptedFilesBox),
  );

  // ── Repositories ──────────────────────────────────────────────────────────
  sl.registerLazySingleton<EncryptionRepository>(
    () => EncryptionRepositoryImpl(
      encryptionService: sl<AesEncryptionService>(),
      localDataSource: sl<EncryptionLocalDataSource>(),
    ),
  );

  // ── Cubits ────────────────────────────────────────────────────────────────
  // Factories ensure each screen receives a fresh instance with clean state.
  sl.registerFactory<EncryptionCubit>(
    () => EncryptionCubit(repository: sl<EncryptionRepository>()),
  );
  sl.registerFactory<HistoryCubit>(
    () => HistoryCubit(repository: sl<EncryptionRepository>()),
  );
}

/// Reads the Hive cipher key from secure storage, generating and persisting
/// one on first launch. The key is the 32-byte payload that
/// [HiveAesCipher] expects.
Future<List<int>> _readOrCreateHiveCipherKey(
  FlutterSecureStorage secureStorage,
) async {
  final existing = await secureStorage.read(key: _kHiveCipherKeyAlias);
  if (existing != null) {
    final bytes = base64Decode(existing);
    if (bytes.length == 32) return bytes;
    // Length mismatch: fall through and regenerate. (Shouldn't happen in
    // normal operation; defensive against partially-written secure storage.)
  }

  final fresh = Hive.generateSecureKey(); // 32 random bytes
  await secureStorage.write(
    key: _kHiveCipherKeyAlias,
    value: base64Encode(fresh),
  );
  return fresh;
}
