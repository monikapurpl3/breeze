// "Why can't it reach the server?", taken apart: for every address the app
// would try, the name lookup, the TCP connection, the TLS handshake (and the
// certificate the server showed) and a plain HTTP request, each timed, each
// failure explained. And the phone's own network: which interfaces are up,
// whether a VPN is, whether the server is on the same subnet as the Wi-Fi.
//
// The checks are this build's own connections, made the way the app makes
// them (dart:io), so they meet the same permissions: on an iPhone, the same
// "local network" permission.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';

import 'forensics.dart';
import 'http_log.dart';
import 'native.dart';

const _timeout = Duration(seconds: 6);

bool isPrivate(InternetAddress a) {
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) {
    return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
  }
  return (b[0] & 0xfe) == 0xfc || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
}

String _ifaceKind(String name) {
  if (name.startsWith('en0')) return 'Wi-Fi';
  if (name.startsWith('en')) return 'Ethernet or Wi-Fi';
  if (name.startsWith('pdp_ip')) return 'cellular';
  if (name.startsWith('utun') || name.startsWith('ipsec') || name.startsWith('ppp')) return 'tunnel (VPN, iCloud Private Relay or a system one)';
  if (name.startsWith('bridge') || name.startsWith('ap')) return 'hotspot';
  if (name.startsWith('awdl') || name.startsWith('llw')) return 'AirDrop/peer-to-peer';
  if (name.startsWith('lo')) return 'loopback';
  return '';
}

/// The phone's interfaces, and what they say: a tunnel with an IPv4 address
/// is usually a VPN (iOS keeps a few utun interfaces with only link-local
/// IPv6 at all times).
Future<List<String>> interfaces() async {
  final out = <String>[];
  try {
    final list = await NetworkInterface.list(includeLinkLocal: true, includeLoopback: false, type: InternetAddressType.any);
    var vpn = false;
    for (final i in list) {
      final kind = _ifaceKind(i.name);
      final addrs = i.addresses.map((a) => a.address).join(', ');
      out.add('${i.name}${kind.isEmpty ? '' : ' ($kind)'}: $addrs');
      if (i.name.startsWith('utun') || i.name.startsWith('ipsec') || i.name.startsWith('ppp')) {
        if (i.addresses.any((a) => a.type == InternetAddressType.IPv4 || !a.isLinkLocal)) vpn = true;
      }
    }
    if (vpn) out.add('=> a tunnel has a routable address: a VPN (or Private Relay) is probably on, and may carry this traffic');
    if (!list.any((i) => i.name.startsWith('en0') && i.addresses.any((a) => a.type == InternetAddressType.IPv4))) {
      out.add('=> no IPv4 on Wi-Fi (en0): not on a Wi-Fi network, so a LAN address cannot be reached');
    }
  } catch (e) {
    out.add('interfaces unavailable: $e');
  }
  return out;
}

/// Whether [target] is in the same /24 (IPv4) as one of the phone's
/// addresses: a rough "is it on my Wi-Fi?".
Future<String?> sameSubnet(InternetAddress target) async {
  if (target.type != InternetAddressType.IPv4) return null;
  try {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        if (a.rawAddress[0] == target.rawAddress[0] && a.rawAddress[1] == target.rawAddress[1] && a.rawAddress[2] == target.rawAddress[2]) {
          return 'same /24 as ${i.name} ${a.address}';
        }
      }
    }
    return 'not on any of the phone\'s /24 networks';
  } catch (_) {
    return null;
  }
}

String _certLine(X509Certificate c) {
  final sha = const DartSha256().hashSync(c.der).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  final now = DateTime.now();
  final days = c.endValidity.difference(now).inDays;
  final state = now.isBefore(c.startValidity) ? 'NOT YET VALID' : now.isAfter(c.endValidity) ? 'EXPIRED' : '$days days left';
  return 'subject ${c.subject}\n      issuer ${c.issuer}\n      valid ${c.startValidity.toIso8601String().substring(0, 10)} to '
      '${c.endValidity.toIso8601String().substring(0, 10)} ($state)\n      SHA-256 $sha';
}

/// Probe one address the app would use. [say] gets each line as it comes.
Future<void> probe(String url, void Function(String) say) async {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) {
    say('$url: not an address');
    return;
  }
  final https = u.scheme == 'https';
  final port = u.hasPort ? u.port : (https ? 443 : 80);
  say('== $url  (host ${u.host}, port $port, ${https ? 'TLS' : 'no TLS'})');

  // 1. The name.
  List<InternetAddress> addrs;
  final literal = InternetAddress.tryParse(u.host);
  if (literal != null) {
    addrs = [literal];
    say('  name: an address already, no lookup');
  } else {
    final c = Stopwatch()..start();
    try {
      addrs = await InternetAddress.lookup(u.host).timeout(_timeout);
      say('  DNS: ${c.elapsedMilliseconds} ms -> ${addrs.map((a) => '${a.address}${isPrivate(a) ? ' (private)' : ''}').join(', ')}');
    } catch (e) {
      say('  DNS FAILED after ${c.elapsedMilliseconds} ms: ${describeError(e)}');
      if (u.host.endsWith('.local')) {
        say('  a .local name is resolved by Bonjour on the local network, which needs the Local Network permission');
      }
      return;
    }
  }

  // 2. TCP, to each address (the first three).
  InternetAddress? reached;
  for (final a in addrs.take(3)) {
    final where = a.isLoopback ? 'loopback' : isPrivate(a) ? (await sameSubnet(a) ?? '') : 'public address';
    final c = Stopwatch()..start();
    try {
      final s = await Socket.connect(a, port, timeout: _timeout);
      say('  TCP ${a.address}:$port: connected in ${c.elapsedMilliseconds} ms from ${s.address.address}:${s.port} ($where)');
      s.destroy();
      reached ??= a;
    } catch (e) {
      say('  TCP ${a.address}:$port FAILED after ${c.elapsedMilliseconds} ms: ${describeError(e)} ($where)');
    }
    // On a LAN address, iOS's own verdict on the local network permission.
    if (isPrivate(a) && !a.isLoopback) {
      final n = await nativeConnect(a.address, port);
      if (n != null) {
        final reason = '${n['unsatisfiedReason'] ?? ''}';
        say('  iOS networking to ${a.address}:$port: ${n['state']} in ${n['ms'] ?? '?'} ms'
            '${n['error'] == null ? '' : ', ${n['error']}'}${reason.isEmpty ? '' : ', reason $reason'}');
        if (reason.contains('localNetworkDenied')) {
          say('  => LOCAL NETWORK PERMISSION DENIED: Settings > Privacy & Security > Local Network > Breeze, switch it on');
        }
      }
    }
  }
  if (reached == null) {
    say('  => no address answered on port $port');
    return;
  }

  // 3. TLS: as the app would (the system's trust), then for a look at the
  // certificate even if the system refuses it.
  if (https) {
    final c = Stopwatch()..start();
    try {
      final s = await SecureSocket.connect(u.host, port, timeout: _timeout);
      final cert = s.peerCertificate;
      say('  TLS: trusted by iOS, handshake ${c.elapsedMilliseconds} ms${s.selectedProtocol == null ? '' : ', ALPN ${s.selectedProtocol}'}');
      if (cert != null) say('    certificate ${_certLine(cert)}');
      s.destroy();
    } catch (e) {
      say('  TLS FAILED after ${c.elapsedMilliseconds} ms: ${describeError(e)}');
      say('  => the app refuses this server\'s certificate. What it shows:');
      X509Certificate? seen;
      try {
        final s = await SecureSocket.connect(u.host, port, timeout: _timeout, onBadCertificate: (cert) {
          seen = cert;
          return true;
        });
        s.destroy();
      } catch (_) {}
      say(seen == null ? '    (none could be read)' : '    certificate ${_certLine(seen!)}');
    }
  }

  // 4. HTTP: the server's health route, which needs no key.
  final client = HttpClient()
    ..connectionTimeout = _timeout
    ..badCertificateCallback = (_, _, _) => true;
  final c = Stopwatch()..start();
  try {
    final req = await client.getUrl(u.replace(path: '/api/health', query: null)).timeout(_timeout);
    final resp = await req.close().timeout(_timeout);
    final body = await resp.transform(utf8.decoder).join().timeout(_timeout);
    say('  HTTP GET /api/health: ${resp.statusCode} in ${c.elapsedMilliseconds} ms: '
        '${body.length > 200 ? '${body.substring(0, 200)}…' : body}${https ? ' (certificate not checked for this request)' : ''}');
    final server = resp.headers.value('server');
    if (server != null) say('    server header: $server');
  } catch (e) {
    say('  HTTP GET /api/health FAILED after ${c.elapsedMilliseconds} ms: ${describeError(e)}');
  } finally {
    client.close(force: true);
  }
}

/// Every probe, for [urls], one after the other, logged as it goes.
Future<String> runProbes(List<String> urls, {void Function(String)? live}) async {
  final out = StringBuffer();
  void say(String l) {
    out.writeln(l);
    live?.call(l);
    flog('probe', l);
  }

  say('Probes at ${DateTime.now().toIso8601String()}');
  say('The phone\'s network:');
  for (final l in await interfaces()) {
    say('  $l');
  }
  if (urls.isEmpty) say('No server address saved yet.');
  for (final url in urls) {
    await probe(url, say);
  }
  return out.toString();
}
