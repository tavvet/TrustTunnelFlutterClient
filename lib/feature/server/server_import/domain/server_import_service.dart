import 'package:trusttunnel/common/models/value_data.dart';
import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';
import 'package:trusttunnel/data/repository/routing_repository.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/feature/server/server_details/domain/service/server_details_service.dart';

/// Prepares an imported endpoint for review. Nothing is saved until confirmation.
class ServerImportService {
  final DeepLinkRepository links;
  final ServerRepository servers;
  final RoutingRepository routing;
  final ServerDetailsService _validator = ServerDetailsServiceImpl();

  ServerImportService({required this.links, required this.servers, required this.routing});

  Future<ServerData> decode(String link) async {
    final decoded = await links.parseDataFromLink(deepLink: link.trim());
    final existing = await servers.getAllServers();
    final names = existing.map((server) => server.serverData.name.trim().toLowerCase()).toSet();
    final baseName = decoded.name.trim().isNotEmpty ? decoded.name.trim() : decoded.domain.trim();
    var name = baseName;
    for (var suffix = 2; names.contains(name.toLowerCase()); suffix++) {
      name = '$baseName $suffix';
    }

    final data = decoded.copyWith(
      name: name,
      ipAddress: decoded.ipAddress.trim(),
      domain: decoded.domain.trim(),
      // Credentials are opaque: whitespace can be part of a username or password.
      dnsServers: decoded.dnsServers.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList(),
      tlsPrefix: ValueData(_optional(decoded.tlsPrefix)),
      customSni: ValueData(_optional(decoded.customSni)),
      routingProfileId: RoutingProfileUtils.defaultRoutingProfileId,
      selected: false,
    );
    _validate(data, names);
    return data;
  }

  Future<void> save(ServerData data) async {
    final existing = await servers.getAllServers();
    _validate(data, existing.map((server) => server.serverData.name).toSet());
    final profile = await routing.getProfileById(id: data.routingProfileId);
    if (profile == null) {
      throw StateError('The routing profile is unavailable.');
    }
    await servers.addNewServer(request: data);
  }

  void _validate(ServerData data, Set<String> names) {
    if (_validator.validateData(data: data, otherServersNames: names).isNotEmpty) {
      // Never attach the link or credentials to an exception or log message.
      throw const FormatException('Invalid server configuration.');
    }
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
