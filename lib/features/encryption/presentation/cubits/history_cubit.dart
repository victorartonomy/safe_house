import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/encrypted_file.dart';
import '../../domain/repositories/encryption_repository.dart';

part 'history_state.dart';

/// Manages the list of previously encrypted files stored in Hive.
///
/// Registered as a **factory** in GetIt.
///
/// ### Typical usage
/// ```dart
/// context.read<HistoryCubit>().loadHistory();
/// ```
class HistoryCubit extends Cubit<HistoryState> {
  final EncryptionRepository _repository;

  HistoryCubit({required EncryptionRepository repository})
      : _repository = repository,
        super(const HistoryInitial());

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Loads all history records from Hive, sorted newest-first.
  Future<void> loadHistory() async {
    emit(const HistoryLoading());
    try {
      final records = await _repository.getHistory();
      emit(HistoryLoaded(records: records));
    } on Failure catch (f) {
      emit(HistoryError(message: f.message));
    } catch (e) {
      emit(HistoryError(message: 'Failed to load history: $e'));
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  /// Deletes a single record by [id] and refreshes the list.
  Future<void> deleteEntry(String id) async {
    try {
      await _repository.deleteHistoryEntry(id);
      // Refresh in-place without showing a full loading spinner.
      await _refreshSilently();
    } on Failure catch (f) {
      emit(HistoryError(message: f.message));
    } catch (e) {
      emit(HistoryError(message: 'Failed to delete entry: $e'));
    }
  }

  /// Deletes all records and emits an empty [HistoryLoaded].
  Future<void> clearHistory() async {
    try {
      await _repository.clearHistory();
      emit(const HistoryLoaded(records: []));
    } on Failure catch (f) {
      emit(HistoryError(message: f.message));
    } catch (e) {
      emit(HistoryError(message: 'Failed to clear history: $e'));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Re-fetches records without emitting [HistoryLoading], preventing the
  /// list from flickering on mutations like delete.
  Future<void> _refreshSilently() async {
    try {
      final records = await _repository.getHistory();
      emit(HistoryLoaded(records: records));
    } on Failure catch (f) {
      emit(HistoryError(message: f.message));
    } catch (e) {
      emit(HistoryError(message: 'Failed to refresh history: $e'));
    }
  }
}
