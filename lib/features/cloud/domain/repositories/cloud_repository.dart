import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';

abstract class CloudRepository {
  Future<Either<Failure, void>> uploadFile({
    required String filePath,
    required String remoteFileName,
  });

  Future<Either<Failure, void>> deleteAllCloudFiles();

  Future<Either<Failure, bool>> isCloudStorageEnabled();

  Future<Either<Failure, void>> setCloudStorageEnabled(bool enabled);
}
