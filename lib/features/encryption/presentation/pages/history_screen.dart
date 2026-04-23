import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../../injection_container.dart';
import '../../domain/entities/encrypted_file.dart';
import '../cubits/history_cubit.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
    builder: (_) => BlocProvider(
      create: (_) => sl<HistoryCubit>()..loadHistory(),
      child: const HistoryScreen(),
    ),
  );

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// IDs of records whose keys are currently revealed.
  /// Using a [Set] gives O(1) lookup — efficient even for large lists.
  final Set<String> _revealedIds = {};

  void _toggleKeyVisibility(String id) {
    setState(() {
      if (_revealedIds.contains(id)) {
        _revealedIds.remove(id);
      } else {
        _revealedIds.add(id);
      }
    });
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Clear History'),
        content: const Text(
          'This will permanently delete all saved records and keys. '
          'Encrypted files on disk will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF4D4D),
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<HistoryCubit>().clearHistory();
      _revealedIds.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        leading: const BackButton(),
        actions: [
          BlocBuilder<HistoryCubit, HistoryState>(
            builder: (context, state) {
              final hasRecords =
                  state is HistoryLoaded && state.records.isNotEmpty;
              if (!hasRecords) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => _confirmClearAll(context),
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: const Color(0xFFFF4D4D).withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<HistoryCubit, HistoryState>(
        builder: (context, state) {
          if (state is HistoryInitial) return const SizedBox.shrink();

          if (state is HistoryLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is HistoryError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFFF4D4D),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.message,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () =>
                          context.read<HistoryCubit>().loadHistory(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is HistoryLoaded) {
            final records = state.records;
            if (records.isEmpty) return _EmptyView();
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              itemCount: records.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final record = records[index];
                return _HistoryItemCard(
                  record: record,
                  isKeyRevealed: _revealedIds.contains(record.id),
                  onToggleKeyVisibility: () => _toggleKeyVisibility(record.id),
                  onDelete: () =>
                      context.read<HistoryCubit>().deleteEntry(record.id),
                );
              },
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ── History item card ──────────────────────────────────────────────────────

class _HistoryItemCard extends StatelessWidget {
  final EncryptedFile record;
  final bool isKeyRevealed;
  final VoidCallback onToggleKeyVisibility;
  final VoidCallback onDelete;

  const _HistoryItemCard({
    required this.record,
    required this.isKeyRevealed,
    required this.onToggleKeyVisibility,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final dateStr = DateFormat(
      'MMM d, yyyy · h:mm a',
    ).format(record.createdAt.toLocal());

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.insert_drive_file_outlined,
                    color: accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.originalName,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(dateStr, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                // Delete button
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: const Color(0xFFFF4D4D).withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 20, color: theme.colorScheme.outline),
          ),

          // ── Encrypted file path ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _DataRow(
              label: 'ENCRYPTED FILE',
              value: p.basename(record.encryptedPath),
              copyValue: record.encryptedPath,
              copyLabel: 'Path',
            ),
          ),

          const SizedBox(height: 10),

          // ── Secret key (obscured by default) ────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SECRET KEY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isKeyRevealed ? record.secretKey : '•' * 32,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            letterSpacing: isKeyRevealed ? 0.4 : 2.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Eye toggle
                      _SmallIconBtn(
                        icon: isKeyRevealed
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        tooltip: isKeyRevealed ? 'Hide key' : 'Reveal key',
                        onTap: onToggleKeyVisibility,
                        color: isKeyRevealed ? accent : null,
                      ),
                      // Copy (only when revealed)
                      if (isKeyRevealed)
                        _SmallIconBtn(
                          icon: Icons.copy_outlined,
                          tooltip: 'Copy key',
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: record.secretKey),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Key copied to clipboard',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small reusables ────────────────────────────────────────────────────────

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final String copyValue;
  final String copyLabel;

  const _DataRow({
    required this.label,
    required this.value,
    required this.copyValue,
    required this.copyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            _SmallIconBtn(
              icon: Icons.copy_outlined,
              tooltip: 'Copy $copyLabel',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: copyValue));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$copyLabel copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _SmallIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 16,
            color: color ?? Theme.of(context).iconTheme.color,
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_outlined,
            size: 52,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('No history yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Files you encrypt will appear here.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
