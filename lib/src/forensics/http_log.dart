// Every HTTP exchange the app makes, recorded: method, address, headers and
// bodies (credentials redacted), status, timing, and any failure with its
// OS error. The last ones are kept for the viewer's Network tab; each is also
// a line in the log.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'forensics.dart';
import 'redact.dart';

class Exchange {
  Exchange(this.id, this.method, this.url, this.requestHeaders, this.requestBody);
  final int id;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final String requestBody;
  final DateTime at = DateTime.now();
  int? status;
  Map<String, String> responseHeaders = const {};
  String responseBody = '';
  int? ms;
  String? error;

  /// An event stream: its chunks are counted, not kept.
  bool streaming = false;
  int chunks = 0;
  int bytes = 0;

  String get summary {
    final s = error != null ? 'FAILED' : status == null ? '…' : '$status';
    final t = ms == null ? '' : ' ${ms}ms';
    final st = streaming ? ' stream: $chunks chunks, $bytes B' : '';
    return '#$id $method ${Uri.tryParse(url)?.path ?? url} -> $s$t$st';
  }

  String get detail {
    final b = StringBuffer()
      ..writeln('#$id $method $url')
      ..writeln('at ${at.toIso8601String()}${ms == null ? '' : ', $ms ms'}')
      ..writeln()
      ..writeln('Request headers:');
    requestHeaders.forEach((k, v) => b.writeln('  $k: $v'));
    if (requestBody.isNotEmpty) {
      b
        ..writeln('Request body:')
        ..writeln(requestBody);
    }
    b.writeln();
    if (error != null) b.writeln('Failed: $error');
    if (status != null) {
      b.writeln('Status $status');
      b.writeln('Response headers:');
      responseHeaders.forEach((k, v) => b.writeln('  $k: $v'));
      if (streaming) b.writeln('Event stream: $chunks chunks, $bytes bytes so far');
      if (responseBody.isNotEmpty) {
        b
          ..writeln('Response body:')
          ..writeln(responseBody);
      }
    }
    return b.toString();
  }
}

class HttpRecorder {
  HttpRecorder._();
  static final HttpRecorder I = HttpRecorder._();
  static const _keep = 400;
  static const bodyLimit = 16 * 1024;

  final _list = ListQueue<Exchange>();
  final ValueNotifier<int> changes = ValueNotifier(0);
  int _next = 1;
  int failures = 0;

  List<Exchange> get exchanges => List.unmodifiable(_list);

  Exchange _begin(String method, String url, Map<String, String> headers, String body) {
    final e = Exchange(_next++, method, redactUrl(url), redactHeaders(headers), body);
    _list.addLast(e);
    while (_list.length > _keep) {
      _list.removeFirst();
    }
    _changed();
    return e;
  }

  bool _announcing = false;

  /// After the current frame and in one go, as Forensics does its lines.
  void _changed() {
    if (_announcing) return;
    _announcing = true;
    scheduleMicrotask(() {
      _announcing = false;
      changes.value++;
    });
  }
}

String _clip(String s) => s.length <= HttpRecorder.bodyLimit
    ? s
    : '${s.substring(0, HttpRecorder.bodyLimit)}\n… (${s.length - HttpRecorder.bodyLimit} more characters)';

String _bodyText(List<int> bytes) {
  if (bytes.isEmpty) return '';
  try {
    return _clip(redactText(utf8.decode(bytes)));
  } catch (_) {
    return '<${bytes.length} bytes, not UTF-8>';
  }
}

/// What an OS error number means for reaching a Breeze Core server, on iOS
/// above all (Darwin's numbers; Linux's where they differ).
String explainOsError(int code) => switch (code) {
      61 || 111 => 'connection refused: the host answered, but nothing listens on that port (server down, wrong port)',
      60 || 110 => 'timed out: no answer at all (wrong address, the host is off, or a firewall drops it)',
      65 || 113 => 'no route to host: on an iPhone, the usual sign that Breeze is NOT allowed on the local network '
          '(Settings > Privacy & Security > Local Network), or the phone is not on that network',
      51 || 101 => 'network unreachable: no network that leads there (Wi-Fi off, or a VPN in the way)',
      50 || 100 => 'network down',
      64 || 112 => 'host down',
      54 || 104 => 'connection reset by the server (or something between)',
      32 => 'broken pipe: the connection was closed while sending',
      8 || -2 => 'the name could not be resolved: DNS does not know it (a .local name needs the local network permission)',
      _ => 'OS error $code',
    };

String describeError(Object e) {
  if (e is SocketException) {
    final os = e.osError;
    final code = os == null ? null : '${os.errorCode} ${os.message}';
    final why = os == null ? '' : ' -- ${explainOsError(os.errorCode)}';
    return 'SocketException: ${e.message}${code == null ? '' : ' (errno $code)'}${e.address == null ? '' : ' to ${e.address!.address}${e.port == null ? '' : ':${e.port}'}'}$why';
  }
  if (e is HandshakeException) return 'TLS handshake failed: ${e.message}${e.osError == null ? '' : ' (${e.osError})'}';
  if (e is TimeoutException) return 'timed out after ${e.duration}';
  return redactText('$e');
}

/// The app's HTTP client in the forensic build: the real one, recorded.
class ForensicHttpClient extends http.BaseClient {
  ForensicHttpClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? _bodyText(request.bodyBytes) : '';
    final ex = HttpRecorder.I._begin(request.method, request.url.toString(), request.headers, body);
    final clock = Stopwatch()..start();
    flog('http', '-> ${ex.summary}', level: Level.debug);
    http.StreamedResponse r;
    try {
      r = await _inner.send(request);
    } catch (e, st) {
      ex
        ..ms = clock.elapsedMilliseconds
        ..error = describeError(e);
      HttpRecorder.I.failures++;
      HttpRecorder.I._changed();
      flog('http', '<- ${ex.summary}: ${ex.error}', level: Level.warn);
      Error.throwWithStackTrace(e, st);
    }
    ex
      ..status = r.statusCode
      ..responseHeaders = redactHeaders(r.headers);
    final type = r.headers['content-type'] ?? '';
    if (type.startsWith('text/event-stream')) {
      // Live: pass every chunk on at once, and count it.
      ex
        ..streaming = true
        ..ms = clock.elapsedMilliseconds;
      HttpRecorder.I._changed();
      flog('http', '<- ${ex.summary} (event stream open)');
      final counted = r.stream.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          ex.chunks++;
          ex.bytes += chunk.length;
          if (ex.chunks <= 3 || ex.chunks % 50 == 0) {
            flog('sse', '#${ex.id} chunk ${ex.chunks}: ${_bodyText(chunk).replaceAll('\n', ' ⏎ ')}', level: Level.debug);
          }
          HttpRecorder.I._changed();
          sink.add(chunk);
        },
        handleError: (e, st, sink) {
          ex.error = describeError(e);
          flog('sse', '#${ex.id} stream error after ${ex.chunks} chunks: ${ex.error}', level: Level.warn);
          HttpRecorder.I._changed();
          sink.addError(e, st);
        },
        handleDone: (sink) {
          flog('sse', '#${ex.id} stream closed after ${ex.chunks} chunks, ${ex.bytes} B, ${clock.elapsed.inSeconds} s');
          HttpRecorder.I._changed();
          sink.close();
        },
      ));
      return http.StreamedResponse(counted, r.statusCode,
          contentLength: r.contentLength,
          request: r.request,
          headers: r.headers,
          isRedirect: r.isRedirect,
          persistentConnection: r.persistentConnection,
          reasonPhrase: r.reasonPhrase);
    }
    // Whole: read it, keep a copy, hand it on unchanged.
    final List<int> bytes;
    try {
      bytes = await r.stream.toBytes();
    } catch (e, st) {
      ex
        ..ms = clock.elapsedMilliseconds
        ..error = 'reading the body: ${describeError(e)}';
      HttpRecorder.I.failures++;
      HttpRecorder.I._changed();
      flog('http', '<- ${ex.summary}: ${ex.error}', level: Level.warn);
      Error.throwWithStackTrace(e, st);
    }
    ex
      ..ms = clock.elapsedMilliseconds
      ..responseBody = _bodyText(bytes);
    HttpRecorder.I._changed();
    final level = r.statusCode >= 500 ? Level.warn : r.statusCode >= 400 ? Level.warn : Level.info;
    flog('http', '<- ${ex.summary}${r.statusCode >= 400 ? ': ${ex.responseBody}' : ''}', level: level);
    return http.StreamedResponse(Stream.value(bytes), r.statusCode,
        contentLength: bytes.length,
        request: r.request,
        headers: r.headers,
        isRedirect: r.isRedirect,
        persistentConnection: r.persistentConnection,
        reasonPhrase: r.reasonPhrase);
  }

  @override
  void close() => _inner.close();
}

/// The client ApiClient makes when it is given none.
http.Client newHttpClient() => kForensics ? ForensicHttpClient(http.Client()) : http.Client();
