import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_datasource_impl.dart';
import 'package:trusttunnel/data/model/certificate.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:vpn_plugin/deep_link_manager.dart';
import 'package:vpn_plugin/models/configuration.dart';

void main() {
  late AppDatabase database;
  late ServerDataSourceImpl source;

  setUp(() {
    database = AppDatabase.inMemory(
      NativeDatabase.memory(setup: (connection) => connection.execute('PRAGMA foreign_keys = ON')),
    );
    source = ServerDataSourceImpl(database: database, deepLinkManager: _UnusedDeepLinkManager());
  });

  tearDown(() => database.close());

  test('persists imported server, ordered DNS entries, and certificate without changing existing server', () async {
    final existing = await source.addNewServer(request: _server(name: 'Existing'));
    await source.setSelectedServerId(id: existing.id);
    final existingBefore = await source.getServerById(id: existing.id);
    final request = _server(name: 'Imported', password: ' password with spaces ');

    final imported = await source.addNewServer(request: request);

    expect(imported.serverData, request);
    expect((await source.getServerById(id: imported.id)).serverData, request);
    expect((await source.getServerById(id: existing.id)).serverData, existingBefore.serverData);
    expect(await database.select(database.servers).get(), hasLength(2));
    expect(await database.select(database.dnsServers).get(), hasLength(4));
    expect(await database.select(database.certificateTable).get(), hasLength(2));
  });

  test('duplicate DNS failure rolls back the new server and all related rows', () async {
    final existing = await source.addNewServer(request: _server(name: 'Existing'));
    await source.setSelectedServerId(id: existing.id);
    final serversBefore = await database.select(database.servers).get();
    final dnsBefore = await database.select(database.dnsServers).get();
    final certificatesBefore = await database.select(database.certificateTable).get();

    await expectLater(
      source.addNewServer(
        request: _server(name: 'Rejected').copyWith(dnsServers: ['1.1.1.1', '1.1.1.1']),
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('UNIQUE constraint failed: dns_servers.server_id, dns_servers.data'),
          'a duplicate DNS constraint error',
        ),
      ),
    );

    expect(await database.select(database.servers).get(), serversBefore);
    expect(await database.select(database.dnsServers).get(), dnsBefore);
    expect(await database.select(database.certificateTable).get(), certificatesBefore);
    expect((await source.getAllServers()).map((server) => server.id), [existing.id]);
  });
}

ServerData _server({required String name, String password = 'password'}) => ServerData(
  name: name,
  ipAddress: '192.0.2.1:443',
  domain: 'vpn.example.com',
  username: 'user',
  password: password,
  vpnProtocol: VpnProtocol.quic,
  dnsServers: const ['1.1.1.1', 'https://dns.example.com/dns-query'],
  routingProfileId: '0',
  ipv6: false,
  tlsPrefix: '0102/ffff',
  customSni: 'edge.example.com',
  certificate: const Certificate(
    name: 'certificate.pem',
    data: '-----BEGIN CERTIFICATE-----\nVEVTVA==\n-----END CERTIFICATE-----',
  ),
);

class _UnusedDeepLinkManager implements DeepLinkManager {
  @override
  Future<Configuration> getConfigurationByBase64({required String base64}) =>
      throw StateError('Persistence must not decode a deep link');
}
