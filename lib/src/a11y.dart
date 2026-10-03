// Small helpers for what screen readers say, shared by the screens.

/// "JH7S-XT2P" read letter by letter -- "J H 7 S, X T 2 P" -- rather than as
/// two words a screen reader guesses at. The web panel reads it the same way.
String spelled(String code) =>
    code.split('-').map((part) => part.split('').join(' ')).join(', ');

/// How long before a pairing code runs out that the app says so.
const int kPairingWarnAtSeconds = 15;
