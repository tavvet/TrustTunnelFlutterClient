import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/data/model/routing_profile.dart';
import 'package:trusttunnel/data/model/routing_profile_data.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';
import 'package:trusttunnel/data/repository/routing_repository.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/feature/server/server_import/domain/server_import_service.dart';

const _valid = ServerData.empty(
  name: 'Home',
  ipAddress: '192.0.2.1:443',
  domain: 'vpn.example.com',
  username: ' user ',
  password: ' secret ',
  dnsServers: ['1.1.1.1', ' 1.1.1.1 ', ''],
);

void main() {
  test('review preparation preserves credentials and avoids duplicate DNS/name entries', () async {
    final servers = _Servers([
      Server(
        id: '1',
        serverData: _valid.copyWith(name: ' home '),
      ),
      Server(
        id: '2',
        serverData: _valid.copyWith(name: 'HOME 2'),
      ),
    ]);
    final service = ServerImportService(links: _Links(_valid), servers: servers, routing: _Routing());

    final data = await service.decode('tt://?test');
    expect(data.name, 'Home 3');
    expect(data.username, ' user ');
    expect(data.password, ' secret ');
    expect(data.dnsServers, ['1.1.1.1']);
    expect(data.routingProfileId, RoutingProfileUtils.defaultRoutingProfileId);
    expect(servers.items, hasLength(2), reason: 'Preparing a preview must not save anything.');

    await service.save(data);
    expect(servers.items, hasLength(3));
    expect(servers.items.last.serverData, data);
  });

  test('unnamed endpoints get a useful name and invalid endpoints never get saved', () async {
    final servers = _Servers([]);
    final service = ServerImportService(
      links: _Links(_valid.copyWith(name: '')),
      servers: servers,
      routing: _Routing(),
    );
    expect((await service.decode('tt://?test')).name, 'vpn.example.com');
    final invalid = ServerImportService(
      links: _Links(_valid.copyWith(password: '')),
      servers: servers,
      routing: _Routing(),
    );
    await expectLater(invalid.decode('tt://?test'), throwsFormatException);
    expect(servers.items, isEmpty);
  });

  test('confirmation revalidates names and refuses a missing routing profile', () async {
    final servers = _Servers([]);
    final routing = _Routing();
    final service = ServerImportService(links: _Links(_valid), servers: servers, routing: routing);
    final data = await service.decode('tt://?test');
    servers.items.add(Server(id: 'other', serverData: data));
    await expectLater(service.save(data), throwsFormatException);
    expect(servers.items, hasLength(1));
    servers.items.clear();
    routing.available = false;
    await expectLater(service.save(data), throwsStateError);
    expect(servers.items, isEmpty);
  });
}

class _Links implements DeepLinkRepository {
  final ServerData value;
  _Links(this.value);
  @override
  Future<ServerData> parseDataFromLink({required String deepLink}) async => value;
}

class _Servers implements ServerRepository {
  final List<Server> items;
  _Servers(this.items);
  @override
  Future<List<Server>> getAllServers() async => List.of(items);
  @override
  Future<Server> addNewServer({required ServerData request}) async {
    final server = Server(id: '${items.length + 1}', serverData: request);
    items.add(server);
    return server;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Routing implements RoutingRepository {
  bool available = true;
  @override
  Future<RoutingProfile?> getProfileById({required String id}) async =>
      available ? RoutingProfile(id: id, data: const RoutingProfileData.empty()) : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
