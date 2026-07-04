import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  Timer? _ticker;
  String? _code;
  DateTime _endsAt = DateTime.now();
  int _remaining = 0;
  bool _expired = false;
  bool _restarting = false;
  int _pollAccum = 0;

  @override
  void initState() {
    super.initState();
    // read initial pairing state after first frame (inherited widgets
    // aren't available during initState)
    WidgetsBinding.instance.addPostFrameCallback((_) => _seed());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _seed() {
    final c = AppScope.of(context);
    setState(() {
      _code = c.userCode;
      _endsAt = DateTime.now().add(Duration(seconds: c.expiresIn));
      _remaining = c.expiresIn;
      _expired = false;
      _pollAccum = 0;
    });
  }

  Future<void> _tick() async {
    if (!mounted) return;
    final c = AppScope.of(context);
    // detect a fresh code (after restart)
    if (c.userCode != null && c.userCode != _code) {
      _seed();
      return;
    }
    final left = _endsAt.difference(DateTime.now()).inSeconds;
    setState(() {
      _remaining = left < 0 ? 0 : left;
      if (_remaining == 0) _expired = true;
    });
    if (_expired) return;

    _pollAccum++;
    if (_pollAccum >= 2) {
      _pollAccum = 0;
      try {
        final status = await c.pollPairing(); // 'approved' flips stage → Gate swaps us out
        if (status == 'expired' || status == 'unknown') {
          if (mounted) setState(() => _expired = true);
        }
      } catch (_) {
        // transient network error — keep trying
      }
    }
  }

  Future<void> _newCode() async {
    final c = AppScope.of(context);
    setState(() => _restarting = true);
    try {
      await c.restartEnrollment();
      _seed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not get a new code: $e')));
      }
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = AppScope.of(context);
    final code = _code ?? c.userCode ?? '········';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair this device'),
        actions: [
          TextButton(
            onPressed: () => c.changeServer(),
            child: const Text('Change server'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_outlined, size: 48, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text('Your pairing code',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Card(
                    color: scheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            code,
                            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  color: scheme.onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'Copy',
                            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                            icon: Icon(Icons.copy, color: scheme.onPrimaryContainer),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_expired)
                    Column(
                      children: [
                        Text('Code expired', style: TextStyle(color: scheme.error)),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _restarting ? null : _newCode,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Get a new code'),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        LinearProgressIndicator(
                          value: c.expiresIn == 0 ? null : _remaining / c.expiresIn,
                        ),
                        const SizedBox(height: 8),
                        Text('expires in ${_remaining}s · waiting for approval…',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Enter this code in your server’s approval tool within the '
                    'time limit. Approval must be done by an administrator on '
                    'the local network.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
