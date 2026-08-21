import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// The waiting-for-the-server screen, with a cat fact for company.
///
/// The facts are **bundled constants, not fetched**. An app whose whole point is
/// that nothing leaves your network would look pretty silly calling a cat-fact
/// API on startup — it would also be a third permission-shaped thing to explain,
/// a request that fails on a LAN with no route out, and a wait *added* to the
/// wait it is decorating.
class CatFacts {
  static const List<String> all = [
    'A cat has 32 muscles in each ear.',
    'Cats sleep 12 to 16 hours a day, which is most of a working week.',
    'A group of cats is called a clowder.',
    'Cats have a third eyelid, the haw, which sweeps across the eye.',
    "A cat's nose print is as unique as a human fingerprint.",
    'Cats cannot taste sweetness — the receptor gene is broken in all felids.',
    'A domestic cat can sprint at roughly 48 km/h.',
    'Cats walk like camels and giraffes: both right legs, then both left.',
    'The oldest known pet cat was buried with a human in Cyprus 9,500 years ago.',
    'Cats have 24 more bones than humans do.',
    'A cat can rotate its ears 180 degrees.',
    'Purring happens between 25 and 150 Hz, which may help bones heal.',
    'Cats sweat only through their paw pads.',
    'A cat can jump about six times its own length.',
    'Whiskers are roughly as wide as the cat, and are used to judge gaps.',
    'Cats have no collarbone, which is why they fit through narrow spaces.',
    'Adult cats meow at humans far more than at other cats.',
    'A cat’s heart beats about twice as fast as a human’s.',
    'Cats see well at a sixth of the light a human needs.',
    'The record for the loudest purr is about 67 decibels — a conversation.',
    'Cats have around 200 million scent receptors; humans have about 5 million.',
    'A cat’s tail carries about 10% of its bones.',
    'Kittens are born with blue eyes; the adult colour arrives later.',
    'Cats knead with their paws — a behaviour kept from nursing.',
    'A cat’s brain is more similar to a human’s than a dog’s is.',
    'Cats can make over 100 distinct vocal sounds.',
    'The hairless Sphynx still needs regular bathing, for oil rather than hair.',
    'A cat’s field of view is about 200 degrees, against a human’s 180.',
    'Cats prefer water that is moving, which is why taps beat bowls.',
    'A cat spends up to half its waking hours grooming.',
    'Cats have a righting reflex from about three weeks old.',
    'Black cats can be any of 22 breeds recognised for the colour.',
    'A cat’s normal body temperature is around 38.6 °C — warmer than yours.',
    'Cats mark by rubbing: cheeks and flanks carry scent glands.',
    'The heaviest recorded domestic cat weighed over 21 kg. Please do not.',
    'Cats dream, and show the same REM sleep phase humans do.',
    'A cat’s claws retract to keep them sharp for climbing.',
    'Cats respond to their own name; they simply reserve the right not to.',
    'Ancient Egyptians shaved their eyebrows in mourning when a cat died.',
    'A cat can be either right- or left-pawed, and most females are right-pawed.',
  ];

  static String random([Random? rng]) =>
      all[(rng ?? Random()).nextInt(all.length)];
}

/// Spinner plus a rotating cat fact. Use wherever the app is waiting on the
/// server with nothing better to show.
class LoadingCat extends StatefulWidget {
  const LoadingCat({
    super.key,
    this.label,
    this.rotate = const Duration(seconds: 7),
  });

  /// What is being waited for, e.g. 'Connecting to Living Room…'.
  final String? label;

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
      if (CatFacts.all.length > 1) {
        while (next == _fact) {
          next = CatFacts.random(_rng);
        }
      }
      setState(() => _fact = next);
    });
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
              Text(
                widget.label!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pets, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'while you wait',
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
