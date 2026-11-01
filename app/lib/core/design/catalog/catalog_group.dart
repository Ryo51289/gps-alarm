import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Titled block inside a catalog section.
final class CatalogGroup extends StatelessWidget {
  const new({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: NapSpace.s12,
      children: [NapSectionHeader(title), ...children],
    );
  }
}

/// Page padding and spacing shared by every section.
final class CatalogSectionBody extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(NapSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: NapSpace.s28,
        children: children,
      ),
    );
  }
}

/// Small secondary caption under a sample.
final class CatalogCaption extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context
          .napStyle(NapTypography.caption)
          .copyWith(color: context.napColors.textSecondary),
    );
  }
}
