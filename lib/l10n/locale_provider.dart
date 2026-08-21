import 'package:flutter/material.dart';

class LocaleProvider extends InheritedWidget {
  final Locale locale;

  const LocaleProvider({super.key, required this.locale, required super.child});

  static Locale of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LocaleProvider>()!.locale;
  }

  @override
  bool updateShouldNotify(LocaleProvider oldWidget) {
    return locale != oldWidget.locale;
  }
}
