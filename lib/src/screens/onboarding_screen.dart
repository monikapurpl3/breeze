import 'package:material_ui/material_ui.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../device_name.dart';
import '../haptics.dart';
import '../l10n.dart';

/// First run. This is the only screen a new user sees before anything works, so
/// it explains what's about to happen rather than presenting three bare fields:
/// the three steps are spelled out up front, the device name arrives
/// pre-filled, and the pairing hand-off is described before it happens instead
/// of surprising them.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _url = TextEditingController();
  final _key = TextEditingController();
  // Pre-filled and re-rollable: every install used to suggest "Breeze", so a
  // household's device list became several identical rows.
  final _label = TextEditingController(text: DeviceName.suggest());
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Remove animations" in Android's accessibility settings: no slide-in.
    if (MediaQuery.disableAnimationsOf(context)) _intro.value = 1;
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _label.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _reroll() {
    Haptics.tick();
    setState(() => _label.text = DeviceName.suggest());
  }

  Future<void> _connect() async {
    final c = AppScope.of(context);
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await c.connect(_url.text, _key.text, _label.text);
      Haptics.success();
      // success → controller flips to the pairing stage; the Gate swaps us out
    } on ApiException catch (e) {
      Haptics.failure();
      setState(
        () => _error = e.unauthorized
            ? l.onboardingKeyRejected
            : l.onboardingConnectFailed(e.message),
      );
    } catch (e) {
      Haptics.failure();
      setState(() => _error = l.onboardingConnectFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final c = AppScope.of(context);
    final l = context.l10n;
    return Scaffold(
      // When this screen is reached from Settings > Servers > Add, the user
      // already has a working server: give them a way back that doesn't
      // require completing a pairing they may have opened by accident.
      appBar: c.addingServer
          ? AppBar(
              backgroundColor: Colors.transparent,
              title: Text(l.serversAdd),
              leading: IconButton(
                tooltip: l.onboardingCancelAdd,
                icon: const Icon(Icons.close),
                onPressed: c.cancelAddServer,
              ),
            )
          : null,
      extendBodyBehindAppBar: true,
      body: Container(
        // A soft wash of the wallpaper accent, so the first screen feels part
        // of the phone rather than a blank form.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.55),
              scheme.surface,
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: FadeTransition(
                  opacity: _intro,
                  child: SlideTransition(
                    position:
                        Tween(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _intro,
                            curve: Curves.easeOut,
                          ),
                        ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(scheme, text),
                        const SizedBox(height: 24),
                        _steps(scheme, text),
                        const SizedBox(height: 26),
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l.onboardingServerAddress,
                            hintText: 'https://climate.example.com',
                            helperText:
                                l.onboardingServerAddressHelper,
                            prefixIcon: const Icon(Icons.dns_outlined),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _key,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l.onboardingAccessKey,
                            helperText: l.onboardingAccessKeyHelper,
                            prefixIcon: const Icon(Icons.key_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? l.onboardingShowKey : l.onboardingHideKey,
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _label,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _busy ? null : _connect(),
                          decoration: InputDecoration(
                            labelText: l.onboardingDeviceName,
                            helperText:
                                l.onboardingDeviceNameHelper,
                            prefixIcon: const Icon(Icons.smartphone_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: l.onboardingSuggestName,
                              icon: const Icon(Icons.casino_outlined),
                              onPressed: _reroll,
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          // Said when it appears: "Connect" otherwise just
                          // went quiet, with the reason only on screen.
                          Semantics(
                            liveRegion: true,
                            container: true,
                            label: l.onboardingErrorSpoken(_error!),
                            excludeSemantics: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 20,
                                    color: scheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: scheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          label: Text(_busy ? l.onboardingConnecting : l.onboardingContinue),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                l.onboardingPrivacy,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme, TextTheme text) => Column(
    children: [
      Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary.withValues(alpha: 0.14),
        ),
        child: Icon(Icons.air, size: 46, color: scheme.primary),
      ),
      const SizedBox(height: 16),
      Text(
        context.l10n.onboardingWelcome,
        textAlign: TextAlign.center,
        style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        context.l10n.onboardingTagline,
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ],
  );

  /// What's about to happen, before it happens — the old screen jumped
  /// straight to a pairing code with no warning that someone has to approve it.
  Widget _steps(ColorScheme scheme, TextTheme text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        _step(
          scheme,
          text,
          '1',
          context.l10n.onboardingStep1Title,
          context.l10n.onboardingStep1Body,
        ),
        const SizedBox(height: 10),
        _step(
          scheme,
          text,
          '2',
          context.l10n.onboardingStep2Title,
          context.l10n.onboardingStep2Body,
        ),
        const SizedBox(height: 10),
        _step(
          scheme,
          text,
          '3',
          context.l10n.onboardingStep3Title,
          context.l10n.onboardingStep3Body,
        ),
      ],
    ),
  );

  Widget _step(
    ColorScheme scheme,
    TextTheme text,
    String n,
    String title,
    String body,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
        ),
        child: Text(
          n,
          style: TextStyle(
            color: scheme.onPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              body,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ],
  );
}
