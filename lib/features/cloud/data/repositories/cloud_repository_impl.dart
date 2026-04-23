import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/repositories/cloud_repository.dart';
import '../datasources/cloud_remote_datasource.dart';

class CloudRepositoryImpl implements CloudRepository {
  final CloudRemoteDataSource remoteDataSource;

  CloudRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, void>> uploadFile({
    required String filePath,
    required String remoteFileName,
  }) async {
    try {
      await remoteDataSource.uploadFile(
        filePath: filePath,
        remoteFileName: remoteFileName,
      );
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteAllCloudFiles() async {
    try {
      await remoteDataSource.deleteAllCloudFiles();
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, bool>> isCloudStorageEnabled() async {
    try {
      final enabled = await remoteDataSource.isCloudStorageEnabled();
      return Right(enabled);
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> setCloudStorageEnabled(bool enabled) async {
    try {
      await remoteDataSource.setCloudStorageEnabled(enabled);
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }
}
