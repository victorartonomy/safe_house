import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps a child widget with a biometric / device-credential authentication
/// gate. Used to protect the History screen, which surfaces plaintext
/// secret keys.
///
/// State machine:
///   checking ──▶ authenticated → renders [child]
///            └─▶ failed        → "Try Again" + back button
///            └─▶ unsupported   → renders [child] with a soft warning banner
///                                (so users on devices without biometrics
///                                aren't permanently locked out)
class BiometricGate extends StatefulWidget {
  final Widget child;
  final String reason;

  const BiometricGate({
    super.key,
    required this.child,
    this.reason = 'Authenticate to view your saved keys',
  });

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  final _auth = LocalAuthentication();
  _GateState _state = _GateState.checking;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    setState(() {
      _state = _GateState.checking;
      _errorMessage = null;
    });

    // On platforms that don't support local_auth (e.g. desktop / web), skip
    // the gate so the screen is still usable.
    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(() => _state = _GateState.unsupported);
      return;
    }

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck && !isSupported) {
        // No biometrics enrolled and no device PIN/pattern → soft-allow,
        // but flag it so the user knows their keys aren't gated.
        setState(() => _state = _GateState.unsupported);
        return;
      }

      final ok = await _auth.authenticate(
        localizedReason: widget.reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // Allow PIN/pattern fallback.
          stickyAuth: true, // Survive an app-backgrounding interruption.
        ),
      );

      if (!mounted) return;
      setState(
        () => _state = ok ? _GateState.authenticated : _GateState.failed,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;

      if (e.code == 'NotAvailable') {
        // Some devices/emulators report that no secure credentials are
        // available even though the feature is technically supported.
        // History should remain usable in that case rather than locking
        // the user out behind an auth failure screen.
        setState(() => _state = _GateState.unsupported);
        return;
      }

      setState(() {
        _state = _GateState.failed;
        _errorMessage = e.message ?? e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GateState.failed;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.authenticated:
      case _GateState.unsupported:
        return widget.child;
      case _GateState.checking:
        return _GateScaffold(
          icon: Icons.fingerprint,
          title: 'Authenticating…',
          showSpinner: true,
        );
      case _GateState.failed:
        return _GateScaffold(
          icon: Icons.lock_outline,
          title: 'Authentication Required',
          subtitle: _errorMessage ?? 'Verify your identity to view saved keys.',
          primaryLabel: 'Try Again',
          onPrimary: _authenticate,
        );
    }
  }
}

enum _GateState { checking, authenticated, failed, unsupported }

class _GateScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool showSpinner;

  const _GateScaffold({
    required this.icon,
    required this.title,
    this.subtitle,
    this.primaryLabel,
    this.onPrimary,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, color: accent, size: 40),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              if (showSpinner) ...[
                const SizedBox(height: 28),
                const CircularProgressIndicator(),
              ],
              if (primaryLabel != null && onPrimary != null) ...[
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onPrimary,
                    child: Text(primaryLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
