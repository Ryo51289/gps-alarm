/// Path helpers shared by the CLI, the profile loader and the validator.
library;

/// Last component of [path]; accepts both `/` and `\` separators.
String fileNameOf(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
