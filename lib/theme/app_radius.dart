// lib/theme/app_radius.dart
// Rayons d'arrondi de l'application.

import 'package:flutter/widgets.dart';

abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}
