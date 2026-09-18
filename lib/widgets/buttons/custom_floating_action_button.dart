import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';
import 'package:trusttunnel/widgets/hover_theme_provider.dart';

enum CustomFloatingActionButtonType {
  extended,
  standart,
  small,
  large,
}

class CustomFloatingActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final CustomFloatingActionButtonType type;
  final String? label;

  const CustomFloatingActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
  }) : type = CustomFloatingActionButtonType.standart,
       label = null;

  const CustomFloatingActionButton.extended({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.label,
  }) : type = CustomFloatingActionButtonType.extended;

  const CustomFloatingActionButton.small({
    super.key,
    required this.icon,
    required this.onPressed,
  }) : type = CustomFloatingActionButtonType.small,
       label = null;

  const CustomFloatingActionButton.large({
    super.key,
    required this.icon,
    required this.onPressed,
  }) : type = CustomFloatingActionButtonType.large,
       label = null;

  @override
  State<CustomFloatingActionButton> createState() => _CustomFloatingActionButtonState();
}

class _CustomFloatingActionButtonState extends State<CustomFloatingActionButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).floatingActionButtonTheme;
    final showFocus =
        _hasFocus && widget.onPressed != null && MediaQuery.navigationModeOf(context) == NavigationMode.directional;
    final baseShape = theme.shape;
    final shape = showFocus
        ? (baseShape is OutlinedBorder ? baseShape : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))
              .copyWith(side: BorderSide(color: context.colors.neutralBlack, width: 3))
        : baseShape;
    final iconWidget = CustomIcon.medium(
      icon: widget.icon,
      color: theme.foregroundColor ?? context.colors.accent,
    );

    final Widget button = switch (widget.type) {
      CustomFloatingActionButtonType.standart => FloatingActionButton(
        onPressed: widget.onPressed,
        shape: shape,
        child: iconWidget,
      ),
      CustomFloatingActionButtonType.extended =>
        widget.label != null
            ? FloatingActionButton.extended(
                onPressed: widget.onPressed,
                shape: shape,
                icon: iconWidget,
                label: Text(
                  widget.label!,
                  style: context.theme.textTheme.labelLarge?.copyWith(color: theme.foregroundColor),
                ),
              )
            : FloatingActionButton(
                onPressed: widget.onPressed,
                shape: shape,
                child: iconWidget,
              ),
      CustomFloatingActionButtonType.small => FloatingActionButton.small(
        onPressed: widget.onPressed,
        shape: shape,
        child: iconWidget,
      ),
      CustomFloatingActionButtonType.large => FloatingActionButton.large(
        onPressed: widget.onPressed,
        shape: shape,
        child: iconWidget,
      ),
    };

    return Focus(
      canRequestFocus: false,
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      child: HoverThemeProvider(child: button),
    );
  }
}
