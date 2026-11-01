import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Package name of the Be Vietnam Pro entry in [LicenseRegistry].
const String kBeVietnamProLicensePackage = 'Be Vietnam Pro';

/// SIL Open Font License 1.1 shipped next to the font files.
const String kBeVietnamProLicenseAsset = 'assets/fonts/BeVietnamPro/OFL.txt';

bool _registered = false;

/// Adds the Be Vietnam Pro license to [LicenseRegistry] once. Only registers
/// a closure; the file is read when the license page opens.
void registerFontLicenses({AssetBundle? bundle}) {
  if (_registered) {
    return;
  }
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await (bundle ?? rootBundle).loadString(
      kBeVietnamProLicenseAsset,
    );
    yield LicenseEntryWithLineBreaks(const [kBeVietnamProLicensePackage], text);
  });
}

/// Allows tests to register again after `LicenseRegistry.reset()`.
@visibleForTesting
void resetFontLicenseRegistration() => _registered = false;
