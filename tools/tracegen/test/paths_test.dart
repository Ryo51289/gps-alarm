import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

void main() {
  test(r'fileNameOf strips / and \ directories', () {
    expect(fileNameOf('a/b/c.gpx'), 'c.gpx');
    expect(
      fileNameOf(r'D:\work\x\train_hn_dh.expect.json'),
      'train_hn_dh.expect.json',
    );
    expect(fileNameOf(r'../mixed\dir/f.json'), 'f.json');
  });

  test(
    'fileNameOf keeps a bare name and returns empty for a trailing slash',
    () {
      expect(fileNameOf('c.gpx'), 'c.gpx');
      expect(fileNameOf('dir/'), '');
    },
  );
}
