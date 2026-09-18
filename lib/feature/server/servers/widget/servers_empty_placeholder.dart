import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_popup.dart';
import 'package:trusttunnel/feature/server/server_import/server_import_actions.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/widgets/default_page.dart';

class ServersEmptyPlaceholder extends StatelessWidget {
  const ServersEmptyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final isTelevision = MediaQuery.navigationModeOf(context) == NavigationMode.directional;
    return DefaultPage.responsive(
      title: context.ln.serversEmptyTitle,
      descriptionText: context.ln.serversEmptyDescription,
      imagePath: AssetImages.server,
      buttonText: isTelevision ? context.ln.importFromPhone : context.ln.create,
      onButtonPressed: () => isTelevision ? importServerFromDevice(context) : _pushServerDetailsScreen(context),
      secondaryButtonText: isTelevision ? context.ln.addServerManually : null,
      onSecondaryButtonPressed: () => _pushServerDetailsScreen(context),
    );
  }

  void _pushServerDetailsScreen(BuildContext context) async {
    final controller = ServersScope.controllerOf(context, listen: false);

    await context.push(
      const ServerDetailsPopUp(),
    );

    controller.fetchServers();
  }
}
