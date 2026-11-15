import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../l10n.dart';

/// The waiting-for-the-server screen, with a cat fact for company.
///
/// The facts are **bundled constants, not fetched**. An app whose whole point is
/// that nothing leaves your network would look pretty silly calling a cat-fact
/// API on startup — it would also be a third permission-shaped thing to explain,
/// a request that fails on a LAN with no route out, and a wait *added* to the
/// wait it is decorating.
class CatFacts {
  /// The bundled facts, in [l]'s language -- English without one. Each
  /// language tells the same forty, translated to stay true rather than word
  /// for word; the English is in lib/l10n/parts/programs_en.arb.
  static List<String> builtIn([AppLocalizations? l]) {
    l ??= lookupAppLocalizations(const Locale('en'));
    return [
      l.catFact1,
      l.catFact2,
      l.catFact3,
      l.catFact4,
      l.catFact5,
      l.catFact6,
      l.catFact7,
      l.catFact8,
      l.catFact9,
      l.catFact10,
      l.catFact11,
      l.catFact12,
      l.catFact13,
      l.catFact14,
      l.catFact15,
      l.catFact16,
      l.catFact17,
      l.catFact18,
      l.catFact19,
      l.catFact20,
      l.catFact21,
      l.catFact22,
      l.catFact23,
      l.catFact24,
      l.catFact25,
      l.catFact26,
      l.catFact27,
      l.catFact28,
      l.catFact29,
      l.catFact30,
      l.catFact31,
      l.catFact32,
      l.catFact33,
      l.catFact34,
      l.catFact35,
      l.catFact36,
      l.catFact37,
      l.catFact38,
      l.catFact39,
      l.catFact40,
    ];
  }

  /// The language the bundled facts are told in: the app's, as the last
  /// [LoadingCat] shown found it. English until one has.
  static AppLocalizations? language;

  /// The bundled facts, in [language].
  static List<String> get all => builtIn(language);

  /// The user's own facts, from the Nerd screen's Internal tab, and whether
  /// the bundled ones stay in the mix. Set once at start and on every change.
  static List<String> custom = const [];
  static bool includeBuiltIn = true;

  /// What is actually shown: the user's facts, the bundled ones, or both.
  /// Never empty -- with nothing of the user's and the bundled ones off, the
  /// bundled ones come back rather than leaving a blank under the spinner.
  static List<String> get pool {
    final mine = custom.where((f) => f.trim().isNotEmpty).toList();
    if (mine.isEmpty) return all;
    return includeBuiltIn ? [...mine, ...all] : mine;
  }

  static String random([Random? rng]) {
    final facts = pool;
    return facts[(rng ?? Random()).nextInt(facts.length)];
  }
}

/// Spinner plus a rotating cat fact. Use wherever the app is waiting on the
/// server with nothing better to show.
class LoadingCat extends StatefulWidget {
  const LoadingCat({
    super.key,
    this.label,
    this.rotate = const Duration(seconds: 7),
    this.live = false,
  });

  /// What is being waited for, e.g. 'Connecting to Living Room…'.
  final String? label;

  /// Say [label] as soon as it shows, for a wait a screen-reader user did not
  /// start and would otherwise not hear about -- the first load after pairing.
  final bool live;

  /// How often to swap the fact. A long wait should not be one static sentence.
  final Duration rotate;

  @override
  State<LoadingCat> createState() => _LoadingCatState();
}

class _LoadingCatState extends State<LoadingCat> {
  final _rng = Random();
  late String _fact = CatFacts.random(_rng);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.rotate, (_) {
      if (!mounted) return;
      // Never repeat the fact that is already on screen: rotating to the same
      // sentence looks like the app has frozen, which is the opposite of the
      // point.
      String next = CatFacts.random(_rng);
      if (CatFacts.pool.length > 1) {
        while (next == _fact) {
          next = CatFacts.random(_rng);
        }
      }
      setState(() => _fact = next);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The bundled facts are told in the app's language: tell CatFacts which,
    // and pick again if it changed under a fact already on screen.
    final l = context.l10n;
    if (CatFacts.language?.localeName != l.localeName) {
      CatFacts.language = l;
      _fact = CatFacts.random(_rng);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            if (widget.label != null) ...[
              Semantics(
                liveRegion: widget.live,
                child: Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pets, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  context.l10n.catWhileYouWait,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Cross-fade rather than a hard swap, and keyed on the text so the
            // animation actually runs when the fact changes.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _fact,
                key: ValueKey(_fact),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
