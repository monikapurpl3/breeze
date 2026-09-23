import 'models.dart';

/// Decides which server replies reach the screen while controls are in flight.
///
/// The app sends one request per tap on + or −, and each reply is the unit's
/// state *after that request*. Showing every reply as it arrived meant that
/// after tapping from 24 up to 29, the replies came back 24.5, 25, 25.5… and
/// the number walked backwards from what had been tapped, then crept up again.
/// A reply that timed out reverted the display to the value before *its* tap,
/// though earlier taps in the burst had gone through. That was "the slider
/// springs back".
///
/// The rules here:
///
/// * only the newest control's reply is shown — older ones describe a moment
///   the user has already moved past;
/// * a failure goes back to what the server last actually reported, not to
///   "before this tap";
/// * while a control is in flight for a unit, pushes and polls for it are
///   recorded but not shown, so a push landing mid-burst cannot flash the old
///   value.
///
/// Pure bookkeeping, no widgets and no network, so it can be tested directly.
class ControlLedger {
  final Map<String, int> _newest = {};
  final Map<String, int> _inFlight = {};
  final Map<String, UnitState> _confirmed = {};

  /// Whether any control for [id] is still waiting on its reply.
  bool isBusy(String id) => (_inFlight[id] ?? 0) > 0;

  /// What the server last actually reported for [id], shown or not.
  UnitState? confirmed(String id) => _confirmed[id];

  /// A control for [id] is about to be sent. Returns its ticket.
  int begin(String id) {
    _inFlight[id] = (_inFlight[id] ?? 0) + 1;
    final ticket = (_newest[id] ?? 0) + 1;
    _newest[id] = ticket;
    return ticket;
  }

  /// The reply to [ticket] arrived. Returns the state to show, or null to leave
  /// the screen as it is because a newer tap is on its way.
  UnitState? replied(String id, int ticket, UnitState state) {
    _confirmed[id] = state;
    return _newest[id] == ticket ? state : null;
  }

  /// [ticket] failed. Returns the state to go back to, or null when a newer
  /// tap is on its way and will settle the display itself. [before] is the
  /// fallback when the server has never reported this unit.
  UnitState? failed(String id, int ticket, UnitState? before) {
    if (_newest[id] != ticket) return null;
    return _confirmed[id] ?? before;
  }

  /// [ticket] is finished, successfully or not.
  void settled(String id) {
    final left = (_inFlight[id] ?? 1) - 1;
    if (left > 0) {
      _inFlight[id] = left;
    } else {
      _inFlight.remove(id);
    }
  }

  /// A push or a poll reported [state]. Returns whether to show it now.
  bool reported(UnitState state) {
    _confirmed[state.id] = state;
    return !isBusy(state.id);
  }

  /// A unit was removed; forget everything about it.
  void forget(String id) {
    _newest.remove(id);
    _inFlight.remove(id);
    _confirmed.remove(id);
  }
}
