import 'package:flutter/material.dart';

/// Editorial display typography — the "atelier" voice.
///
/// Japanese mincho (serif) is used for identity moments: the wordmark, the
/// three mode verbs (整える・読む・書く), screen headings, and empty states.
/// Everyday UI text stays in the platform gothic via [ThemeData]'s
/// `fontFamilyFallback`. Access via `Theme.of(context).extension<AtelierType>()!`.
class AtelierType extends ThemeExtension<AtelierType> {
  const AtelierType({
    required this.display,
    required this.displaySmall,
    required this.verb,
  });

  /// Large screen heading (e.g.「整える」at the top of the library).
  final TextStyle display;

  /// Smaller serif accent (dialog titles, empty-state headings).
  final TextStyle displaySmall;

  /// The sidebar mode verbs.
  final TextStyle verb;

  static const List<String> serifFallback = <String>[
    'Yu Mincho',
    'YuMincho',
    'Hiragino Mincho ProN',
    'Noto Serif CJK JP',
    'Noto Serif JP',
    'Georgia',
    'Times New Roman',
  ];

  static AtelierType of(ColorScheme scheme) => AtelierType(
        display: TextStyle(
          fontFamilyFallback: serifFallback,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          height: 1.3,
          letterSpacing: 1.5,
          color: scheme.onSurface,
        ),
        displaySmall: TextStyle(
          fontFamilyFallback: serifFallback,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          height: 1.35,
          letterSpacing: 1.0,
          color: scheme.onSurface,
        ),
        verb: TextStyle(
          fontFamilyFallback: serifFallback,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: 2.0,
          color: scheme.onSurface,
        ),
      );

  @override
  AtelierType copyWith(
          {TextStyle? display, TextStyle? displaySmall, TextStyle? verb}) =>
      AtelierType(
        display: display ?? this.display,
        displaySmall: displaySmall ?? this.displaySmall,
        verb: verb ?? this.verb,
      );

  @override
  AtelierType lerp(AtelierType? other, double t) {
    if (other == null) return this;
    return AtelierType(
      display: TextStyle.lerp(display, other.display, t)!,
      displaySmall: TextStyle.lerp(displaySmall, other.displaySmall, t)!,
      verb: TextStyle.lerp(verb, other.verb, t)!,
    );
  }
}

/// Atelier's visual identity — a single source of truth for both the light and
/// dark [ThemeData].
///
/// Design direction ("紙とインク" — paper & ink, with an atelier's warmth):
/// - Light: warm off-white "washi" surfaces, sumi-ink text (never pure black),
///   a single terracotta/amber accent.
/// - Dark: warm charcoal surfaces with softened contrast (no pure black/white),
///   the same terracotta accent, lightened for legibility.
/// - Editorial calm: generous whitespace, restrained radii/elevation, section
///   separation by tone and hairline borders rather than heavy cards.
///
/// Every screen must read colors through the [ColorScheme] / component themes
/// defined here — no literal colors in screen code.
class AppTheme {
  AppTheme._();

  /// The accent seed: a warm terracotta. A single accent hue is used across the
  /// app (no multi-color palettes) per the design brief.
  static const Color _seed = Color(0xFFB25B34);

  /// Japanese is the primary UI language. We prefer the platform's native UI
  /// gothic (Yu Gothic UI on Windows, Hiragino Sans on macOS) without bundling
  /// fonts, falling back gracefully elsewhere.
  static const List<String> _fontFallback = <String>[
    'Yu Gothic UI',
    'Hiragino Sans',
    'Hiragino Kaku Gothic ProN',
    'Meiryo',
    'Noto Sans CJK JP',
    'Noto Sans JP',
    'Segoe UI',
  ];

  // ------------------------------------------------------------------
  // Color schemes
  // ------------------------------------------------------------------

  /// Light "washi paper" scheme: warm off-white surfaces, sumi-ink foreground.
  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(seedColor: _seed).copyWith(
    brightness: Brightness.light,
    primary: const Color(0xFFA8511F),
    onPrimary: const Color(0xFFFDF7EF),
    primaryContainer: const Color(0xFFF3DAC6),
    onPrimaryContainer: const Color(0xFF3F1E0B),
    secondary: const Color(0xFF6E6154),
    onSecondary: const Color(0xFFFDF7EF),
    secondaryContainer: const Color(0xFFE7DDCD),
    onSecondaryContainer: const Color(0xFF3A322A),
    tertiary: const Color(0xFF7C6A2E),
    onTertiary: const Color(0xFFFDF7EF),
    error: const Color(0xFF9C4030),
    onError: const Color(0xFFFDF7EF),
    errorContainer: const Color(0xFFF4D9CF),
    onErrorContainer: const Color(0xFF411309),
    surface: const Color(0xFFFAF6EE),
    onSurface: const Color(0xFF2A2521),
    onSurfaceVariant: const Color(0xFF5C5348),
    surfaceContainerLowest: const Color(0xFFFFFDF8),
    surfaceContainerLow: const Color(0xFFF5EFE4),
    surfaceContainer: const Color(0xFFEFE8DB),
    surfaceContainerHigh: const Color(0xFFE9E1D1),
    surfaceContainerHighest: const Color(0xFFE2D9C7),
    outline: const Color(0xFFB4A992),
    outlineVariant: const Color(0xFFD9CFBC),
    inverseSurface: const Color(0xFF322D28),
    onInverseSurface: const Color(0xFFF3ECDF),
  );

  /// Dark "warm charcoal" scheme: softened contrast, same accent hue lightened.
  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark)
          .copyWith(
    brightness: Brightness.dark,
    primary: const Color(0xFFE0A075),
    onPrimary: const Color(0xFF3A1B08),
    primaryContainer: const Color(0xFF59341C),
    onPrimaryContainer: const Color(0xFFF6DAC5),
    secondary: const Color(0xFFCDBFAC),
    onSecondary: const Color(0xFF342C22),
    secondaryContainer: const Color(0xFF453C31),
    onSecondaryContainer: const Color(0xFFE9DECC),
    tertiary: const Color(0xFFD5C08A),
    onTertiary: const Color(0xFF383014),
    error: const Color(0xFFE79A88),
    onError: const Color(0xFF44160C),
    errorContainer: const Color(0xFF6A2C1E),
    onErrorContainer: const Color(0xFFF7D9D0),
    surface: const Color(0xFF1E1B18),
    onSurface: const Color(0xFFE9E1D4),
    onSurfaceVariant: const Color(0xFFB6AB9A),
    surfaceContainerLowest: const Color(0xFF161311),
    surfaceContainerLow: const Color(0xFF221F1B),
    surfaceContainer: const Color(0xFF272420),
    surfaceContainerHigh: const Color(0xFF322E29),
    surfaceContainerHighest: const Color(0xFF3D3833),
    outline: const Color(0xFF7C7264),
    outlineVariant: const Color(0xFF453F38),
    inverseSurface: const Color(0xFFE9E1D4),
    onInverseSurface: const Color(0xFF322D28),
  );

  // ------------------------------------------------------------------
  // Public ThemeData
  // ------------------------------------------------------------------

  static ThemeData get light => _build(_lightScheme);
  static ThemeData get dark => _build(_darkScheme);

  // ------------------------------------------------------------------
  // Builder
  // ------------------------------------------------------------------

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamilyFallback: _fontFallback,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
    );

    // Editorial type scale: clear weight/size hierarchy between headings and
    // body, tuned for a Japanese primary UI (comfortable line height).
    final text = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: scheme.onSurface,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
        letterSpacing: 0.2,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );

    const radius = 10.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    // Shared across the app: dialog titles take the serif display voice, so
    // every AlertDialog reads in the same editorial register without each call
    // site restyling its title.
    final atelierType = AtelierType.of(scheme);

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[atelierType],
      textTheme: text,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        selectedColor: scheme.onPrimaryContainer,
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
        shape: shape,
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle:
            text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: atelierType.displaySmall,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        textStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: scheme.primary),
        hintStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
