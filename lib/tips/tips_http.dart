// The only network the app opens: POSTs to the pig tips project,
// with dart:io's client and no package. release_no_network_test keeps every
// other file free of it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

/// One answer: the status, the headers the client reads (lower-case names)
/// and the body as text.
@immutable
class TipsResponse {
  const TipsResponse(this.status, {this.headers = const {}, this.body = ''});

  final int status;
  final Map<String, String> headers;
  final String body;
}

/// A POST to the tips project. Faked in tests.
abstract interface class TipsHttp {
  /// Any status is an answer. Throws when there's no answer: no connection,
  /// or none within [timeout].
  Future<TipsResponse> post(
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  });
}

class IoTipsHttp implements TipsHttp {
  IoTipsHttp() : _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  final HttpClient _client;

  /// A tip, a token or a short error, never more: a longer body is no answer.
  static const maxBody = 64 * 1024;

  @override
  Future<TipsResponse> post(
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    HttpClientRequest? request;
    Future<TipsResponse> send() async {
      final r = request = await _client.postUrl(url);
      for (final h in headers.entries) {
        r.headers.set(h.key, h.value);
      }
      // A known length, never chunked: the most plain request there is.
      if (body == null) {
        r.contentLength = 0;
      } else {
        final encoded = utf8.encode(body);
        r.headers.contentType = ContentType.json;
        r.contentLength = encoded.length;
        r.add(encoded);
      }
      final response = await r.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maxBody) throw const HttpException('the answer is too long');
      }
      final read = <String, String>{};
      response.headers.forEach((name, values) => read[name.toLowerCase()] = values.join(','));
      return TipsResponse(
        response.statusCode,
        headers: read,
        body: utf8.decode(bytes, allowMalformed: true),
      );
    }

    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      request?.abort();
      rethrow;
    }
  }
}
