import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';

/// Whether this build should draw its own window chrome. The native title bar
/// is hidden only on Windows (macOS keeps its traffic lights until we can
/// verify the overlay there; iOS has no window chrome at all).
bool get useCustomChrome =>
    !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST') && Platform.isWindows;

/// The integrated title bar: the Atelier wordmark on the left, a drag-to-move
/// surface in the middle, and custom minimize / maximize / close buttons on
/// the right. Rendered only when [useCustomChrome] is true — otherwise it
/// degrades to a slim brand strip without window buttons.
class AtelierTitleBar extends StatelessWidget {
  const AtelierTitleBar({super.key});

  static const double height = 42;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bar = Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const _SealMark(),
          const SizedBox(width: 10),
          Text(
            'Atelier',
            style: Theme.of(context)
                .extension<AtelierType>()!
                .displaySmall
                .copyWith(fontSize: 16, letterSpacing: 3.0),
          ),
          const SizedBox(width: 10),
          Text(
            '— 整える・読む・書く',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  letterSpacing: 1.2,
                ),
          ),
          const Spacer(),
          if (useCustomChrome) const _WindowButtons(),
        ],
      ),
    );

    if (!useCustomChrome) return bar;
    return DragToMoveArea(child: bar);
  }
}

/// A hanko-style square seal bearing "A" — the wordmark.
class _SealMark extends StatelessWidget {
  const _SealMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'A',
        style: TextStyle(
          fontFamilyFallback: AtelierType.serifFallback,
          color: scheme.onPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: Icons.remove,
          tooltip: '最小化',
          onPressed: windowManager.minimize,
        ),
        _CaptionButton(
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _maximized ? 13 : 15,
          tooltip: _maximized ? '元に戻す' : '最大化',
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _CaptionButton(
          icon: Icons.close,
          tooltip: '閉じる',
          isClose: true,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 16,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final double iconSize;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoverBg = widget.isClose
        ? const Color(0xFFC42B1C)
        : scheme.onSurface.withValues(alpha: 0.08);
    final fg = _hover && widget.isClose ? Colors.white : scheme.onSurfaceVariant;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 46,
            height: AtelierTitleBar.height,
            color: _hover ? hoverBg : Colors.transparent,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
