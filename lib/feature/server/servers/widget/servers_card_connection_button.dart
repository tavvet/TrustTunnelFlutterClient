import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/extensions/theme_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/widgets/buttons/custom_icon_button.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';
import 'package:trusttunnel/widgets/rotating_wrapper.dart';

class ServersCardConnectionButton extends StatelessWidget {
  final VpnState vpnManagerState;
  final VoidCallback onPressed;
  final String serverId;

  const ServersCardConnectionButton({
    super.key,
    required this.serverId,
    required this.vpnManagerState,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final pending = isPendingResult(vpnManagerState);

    return Theme(
      data: context.theme.copyWith(
        iconButtonTheme: pending
            ? context.theme.extension<CustomFilledIconButtonTheme>()!.iconButtonInProgress
            : context.theme.extension<CustomFilledIconButtonTheme>()!.iconButton,
      ),
      // Keep the button (and its focus node) mounted across VPN state changes.
      // Only the progress icon rotates; the focus indicator stays still.
      child: CustomIconButton.custom(
        onPressed: onPressed,
        selected: vpnManagerState != VpnState.disconnected,
        tooltip: pending
            ? context.ln.cancel
            : vpnManagerState == VpnState.connected
            ? context.ln.disconnect
            : context.ln.connect,
        iconWidget: pending
            ? RotatingWidget(
                duration: const Duration(seconds: 1),
                child: CustomIcon.medium(icon: AssetIcons.update),
              )
            : CustomIcon.medium(icon: AssetIcons.powerSettingsNew),
      ),
    );
  }

  bool isPendingResult(VpnState state) => state != VpnState.connected && state != VpnState.disconnected;
}
