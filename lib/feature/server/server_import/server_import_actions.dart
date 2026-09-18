import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/server_import/domain/server_import_service.dart';
import 'package:trusttunnel/feature/server/server_import/widgets/server_import_screen.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';

Future<void> importServerFromDevice(BuildContext context) async {
  final repositories = context.repositoryFactory;
  final service = ServerImportService(
    links: repositories.deepLinkRepository,
    servers: repositories.serverRepository,
    routing: repositories.routingRepository,
  );
  final result = await context.push<ServerData>(
    ServerImportScreen(decode: service.decode, save: service.save),
  );
  if (!context.mounted || result == null) return;
  ServersScope.controllerOf(context, listen: false).fetchServers();
  context.showInfoSnackBar(message: context.ln.serverCreatedSnackbar(result.name));
}
