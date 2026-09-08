import 'package:flutter/material.dart';

/// Global messenger key so non-widget code (e.g. NotificationService)
/// can show snackbars/banners without a BuildContext.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
