import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

Future<void> registerThirdPartyLicenses() async {
  Future<void> add(String package, String assetPath) async {
    try {
      final text = await rootBundle.loadString(assetPath);
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(<String>[package], text);
      });
    } catch (_) {
      // ignore load failures
    }
  }

  await add('Fonts: FZG', 'assets/licenses/FZG-OFL-1.1.txt');
  await add('Fonts: MiSans (extract)', 'assets/licenses/MiSans-LICENSE.txt');
  await add('Fonts: nfdcs', 'assets/licenses/nfdcs-LICENSE.txt');
}
