// Driver of `flutter drive` runs (T23 TI01, hook of T24 TC37): writes
// `binding.reportData` to build/integration_response_data.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
