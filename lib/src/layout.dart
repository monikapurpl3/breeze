// How big the window is, and what that makes the app look like: one unit per
// screen on a phone, sideways on a phone held sideways, and on a tablet or an
// open foldable the units listed beside the one chosen.
//
// Decided by the space the app actually has, never by the kind of device: a
// tablet in split screen is a phone, and a phone's landscape is landscape.

import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

/// Wide and tall enough for the units list beside a unit: a tablet either way
/// up, an open foldable, a big phone's landscape is not (too short).
bool useListDetail(Size body) => body.width >= 720 && body.height >= 440;

/// The list's width beside a unit: about a third, within reason.
double listPaneWidth(Size body) => (body.width * 0.32).clamp(280.0, 360.0);

/// A unit's page lays out sideways when it is clearly wider than tall.
bool pageIsLandscape(Size page) => page.width >= 560 && page.width > page.height * 1.15;

/// A unit's page with room to spare both ways -- a tablet's, an open
/// foldable's: everything on it is drawn bigger, to fill the whole of it.
bool pageIsRoomy(Size page) => page.shortestSide >= 480 && page.longestSide >= 640;

/// A tablet's window: big both ways, and no fold or hinge through it. Its
/// unit page's parts grow thicker into the height they have spare; an open
/// foldable's -- smaller, and folding down the middle -- keep their own
/// height, with room between them instead.
bool isTabletWindow(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.shortestSide < 600 || size.longestSide < 900) return false;
  return !MediaQuery.displayFeaturesOf(context).any(
      (f) => f.type == DisplayFeatureType.fold || f.type == DisplayFeatureType.hinge);
}

/// A hinge, or a fold bent part way, running top to bottom through the
/// window: the list goes on one side of it and the unit on the other, rather
/// than either across it. A flat fold is no obstacle and is ignored.
Rect? verticalSeparator(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  for (final f in MediaQuery.displayFeaturesOf(context)) {
    final separates = f.type == DisplayFeatureType.hinge ||
        (f.type == DisplayFeatureType.fold && f.state == DisplayFeatureState.postureHalfOpened);
    final b = f.bounds;
    if (separates && b.top <= 0 && b.bottom >= size.height && b.left > 0 && b.right < size.width) {
      return b;
    }
  }
  return null;
}
