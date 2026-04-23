import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class CloudRemoteDataSource {
  Future<void> uploadFile({
    required String filePath,
    required String remoteFileName,
  });

  Future<void> deleteAllCloudFiles();

  Future<bool> isCloudStorageEnabled();

  Future<void> setCloudStorageEnabled(bool enabled);
}

class CloudRemoteDataSourceImpl implements CloudRemoteDataSource {
  final FirebaseStorage firebaseStorage;
  final FirebaseAuth firebaseAuth;
  final SharedPreferences sharedPreferences;

  static const String _cloudStorageEnabledKey = 'cloud_storage_enabled';

  CloudRemoteDataSourceImpl({
    required this.firebaseStorage,
    required this.firebaseAuth,
    required this.sharedPreferences,
  });

  String get _userId {
    final user = firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to access cloud storage.');
    }
    return user.uid;
  }

  @override
  Future<void> uploadFile({
    required String filePath,
    required String remoteFileName,
  }) async {
    final enabled = await isCloudStorageEnabled();
    if (!enabled) {
      throw Exception('Cloud storage is currently disabled in settings.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist.');
    }

    final ref = firebaseStorage.ref().child('users/$_userId/$remoteFileName');
    await ref.putFile(file);
  }

  @override
  Future<void> deleteAllCloudFiles() async {
    final ref = firebaseStorage.ref().child('users/$_userId');
    final listResult = await ref.listAll();

    // Delete all files in the user's directory
    for (var item in listResult.items) {
      await item.delete();
    }
  }

  @override
  Future<bool> isCloudStorageEnabled() async {
    return sharedPreferences.getBool(_cloudStorageEnabledKey) ??
        false; // default disabled
  }

  @override
  Future<void> setCloudStorageEnabled(bool enabled) async {
    await sharedPreferences.setBool(_cloudStorageEnabledKey, enabled);
  }
}
