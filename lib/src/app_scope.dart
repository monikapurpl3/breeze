// Exposes the AppController to the widget tree.

import 'package:flutter/widgets.dart';
import 'app_controller.dart';

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope not found in context');
    return scope!.notifier!;
  }
}
