import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The unified screen header. Every mode opens with its verb set in mincho
/// display type (整える・読む・書く), a quiet gothic subtitle, and optional
/// right-aligned actions. This is the editorial "title page" of each mode and
/// the single place that owns that treatment, so the three modes stay visually
/// in step.
///
/// Settings — not a verb — passes [small] to fall back to the smaller serif
/// ([AtelierType.displaySmall]) rather than the full 28px display.
class ModeHeader extends StatelessWidget {
  const ModeHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.small = false,
  });

  /// The verb (整える / 読む / 書く) or, for non-verb modes, the plain heading.
  final String title;

  /// A quiet one-line gloss under the verb (mode description, open paper, or
  /// current project name). Truncated with an ellipsis.
  final String? subtitle;

  /// Primary actions for this mode, laid out at the trailing edge.
  final List<Widget> actions;

  /// Use the smaller serif ([AtelierType.displaySmall]) instead of the full
  /// display size — for headings that are not one of the three mode verbs.
  final bool small;

  /// Shared outer padding so every mode's content starts on the same margin.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(28, 22, 28, 18);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = theme.extension<AtelierType>()!;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: small ? type.displaySmall : type.display),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ],
      ),
    );
  }
}
