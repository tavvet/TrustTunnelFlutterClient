import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/widgets/buttons/custom_icon_button.dart';

class CustomSnackBar extends SnackBar {
  final bool _showCloseIcon;
  final List<Widget> _trailingActions;

  const CustomSnackBar({
    super.key,
    required super.content,
    super.action,
    super.backgroundColor,
    super.behavior,
    super.duration,
    super.elevation,
    super.margin,
    super.shape,
    this._trailingActions = const [],
    this._showCloseIcon = false,
  });

  @override
  Color? get backgroundColor => Colors.transparent;

  @override
  bool get showCloseIcon => false;

  @override
  EdgeInsetsGeometry? get padding => EdgeInsets.zero;

  @override
  Widget get content => Padding(
    padding: const EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: 16,
    ),
    child: Builder(
      builder: (context) {
        final snackBarTheme = context.theme.snackBarTheme;
        final content = Padding(
          padding: EdgeInsets.only(
            left: 16,
            top: 14,
            right: _showCloseIcon || _trailingActions.isNotEmpty ? 0 : 16,
            bottom: 14,
          ),
          child: super.content,
        );

        return Material(
          shape: snackBarTheme.shape,
          color: snackBarTheme.backgroundColor,
          elevation: snackBarTheme.elevation ?? 0,
          textStyle: snackBarTheme.contentTextStyle,
          shadowColor: context.theme.shadowColor,
          child: Row(
            children: [
              Expanded(
                child: content,
              ),
              if (_trailingActions.isNotEmpty)
                Theme(
                  data: _getActionTheme(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _trailingActions,
                  ),
                ),
              if (_showCloseIcon)
                Theme(
                  data: _getActionTheme(context),
                  child: CustomIconButton(
                    icon: AssetIcons.close,
                    color: snackBarTheme.closeIconColor,
                    onPressed: () =>
                        ScaffoldMessenger.of(
                          context,
                        ).hideCurrentSnackBar(
                          reason: SnackBarClosedReason.dismiss,
                        ),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  @override
  double? get elevation => 0;

  ThemeData _getActionTheme(BuildContext context) {
    final theme = context.theme;
    final foreground = theme.snackBarTheme.closeIconColor ?? context.colors.specialStaticWhite;
    ButtonStyle actionStyle(ButtonStyle? base, Color color) => (base ?? const ButtonStyle()).copyWith(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? color.withValues(alpha: 0.5) : color,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => !states.contains(WidgetState.disabled) && states.contains(WidgetState.focused)
            ? BorderSide(color: foreground, width: 3)
            : BorderSide.none,
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (states.contains(WidgetState.pressed)) return foreground.withValues(alpha: 0.2);
        if (states.contains(WidgetState.focused)) return foreground.withValues(alpha: 0.12);
        if (states.contains(WidgetState.hovered)) return foreground.withValues(alpha: 0.1);
        return Colors.transparent;
      }),
    );

    return theme.copyWith(
      iconButtonTheme: IconButtonThemeData(style: actionStyle(theme.iconButtonTheme.style, foreground)),
      textButtonTheme: TextButtonThemeData(
        style: actionStyle(theme.textButtonTheme.style, theme.snackBarTheme.actionTextColor ?? foreground),
      ),
    );
  }
}
