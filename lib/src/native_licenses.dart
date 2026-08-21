import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Register the licences of the app's **native** dependencies.
///
/// Flutter's [LicenseRegistry] collects LICENSE files from the Dart package
/// graph, which is why `showLicensePage` is always accurate for those and needs
/// no maintenance. It knows nothing about Gradle, so the AndroidX Car App
/// Library that the Android Auto surface is built on — Apache-2.0, whose §4(a)
/// asks that recipients get a copy of the licence — appeared nowhere in the app
/// at all.
///
/// Anything added to `android/app/build.gradle.kts` belongs in this list too.
void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/licenses/APACHE-2.0.txt');
    yield LicenseEntryWithLineBreaks(const [
      'androidx.car.app:app',
      'androidx.car.app:app-projected',
    ], text);
  });
}
