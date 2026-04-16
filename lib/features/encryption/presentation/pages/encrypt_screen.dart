import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../injection_container.dart';
import '../cubits/encryption_cubit.dart';
import '../widgets/file_picker_tile.dart';
import '../widgets/key_field.dart';
import '../widgets/result_card.dart';

class EncryptScreen extends StatefulWidget {
  const EncryptScreen({super.key});

  /// Returns a [MaterialPageRoute] that provides a fresh [EncryptionCubit].
  static Route<void> route() => MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl<EncryptionCubit>(),
          child: const EncryptScreen(),
        ),
      );

  @override
  State<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends State<EncryptScreen> {
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encrypt File'),
        leading: const BackButton(),
      ),
      body: BlocConsumer<EncryptionCubit, EncryptionState>(
        // Only propagate key-generated and errors as side effects;
        // exclude KeyGenerated from triggering a full rebuild.
        listenWhen: (_, current) =>
            current is EncryptionKeyGenerated || current is EncryptionError,
        listener: (context, state) {
          if (state is EncryptionKeyGenerated) {
            _keyController.text = state.generatedKey;
            // Move cursor to end so the generated key is visible.
            _keyController.selection = TextSelection.fromPosition(
              TextPosition(offset: _keyController.text.length),
            );
          }
          if (state is EncryptionError) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFFFF4D4D).withValues(alpha: 0.9),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              );
          }
        },
        buildWhen: (_, current) => current is! EncryptionKeyGenerated,
        builder: (context, state) {
          // ── Success view ─────────────────────────────────────────────
          if (state is EncryptionSuccess) {
            return _SuccessView(
              title: 'File Encrypted',
              filePath: state.result.encryptedPath,
              secretKey: state.result.secretKey,
              originalName: state.result.originalName,
              onEncryptAnother: () =>
                  context.read<EncryptionCubit>().reset(),
            );
          }

          final cubit = context.read<EncryptionCubit>();
          final loadingState = state is EncryptionLoading ? state : null;
          final isLoading = loadingState != null;
          final selectedFile =
              state is EncryptionFileSelected ? state : null;

          // ── Form view ────────────────────────────────────────────────
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select a file and provide a secret key to encrypt it.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),

                // Step 1 — File picker
                _SectionLabel(number: '01', label: 'Choose File'),
                const SizedBox(height: 10),
                FilePickerTile(
                  fileName: selectedFile?.fileName,
                  filePath: selectedFile?.filePath,
                  onTap: isLoading
                      ? () {}
                      : () => cubit.pickFileForEncryption(),
                ),
                const SizedBox(height: 28),

                // Step 2 — Secret key
                _SectionLabel(number: '02', label: 'Secret Key'),
                const SizedBox(height: 10),
                KeyField(
                  controller: _keyController,
                  showGenerateButton: true,
                  onGenerate: isLoading ? null : () => cubit.generateKey(),
                ),
                const SizedBox(height: 36),

                // CTA
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () => cubit.encryptSelectedFile(
                              _keyController.text,
                            ),
                    child: isLoading
                        ? _LoadingRow(
                            message: loadingState.message)
                        : const Text('Encrypt File'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Success screen ─────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final String title;
  final String filePath;
  final String secretKey;
  final String originalName;
  final VoidCallback onEncryptAnother;

  const _SuccessView({
    required this.title,
    required this.filePath,
    required this.secretKey,
    required this.originalName,
    required this.onEncryptAnother,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResultCard(
            isSuccess: true,
            title: title,
            subtitle: 'Original: $originalName',
          ),
          const SizedBox(height: 20),

          // Output path
          _InfoRow(
            label: 'Saved to',
            value: p.basename(filePath),
            fullValue: filePath,
            copyLabel: 'Path',
          ),
          const SizedBox(height: 16),

          // Secret key — prominently displayed with warning
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.key_outlined,
                        color: theme.colorScheme.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Save Your Key',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'This key is saved in History, but store a backup. Without it, the file cannot be decrypted.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ResultCard(
                  isSuccess: true,
                  title: 'Secret Key',
                  copyableValue: secretKey,
                  copyLabel: 'Key',
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onEncryptAnother,
              child: const Text('Encrypt Another File'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small reusable helpers ─────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String number;
  final String label;

  const _SectionLabel({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _LoadingRow extends StatelessWidget {
  final String message;
  const _LoadingRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF0D0D0D),
          ),
        ),
        const SizedBox(width: 10),
        Text(message),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String fullValue;
  final String copyLabel;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.fullValue,
    required this.copyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1)),
        const SizedBox(height: 4),
        ResultCard(
          isSuccess: true,
          title: value,
          copyableValue: fullValue,
          copyLabel: copyLabel,
        ),
      ],
    );
  }
}
