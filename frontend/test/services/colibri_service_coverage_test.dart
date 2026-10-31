// Network-path coverage for ColibriService (health check, chat completion,
// local clinical assistant). A loopback HttpServer stands in for the Colibri
// OpenAI-compatible gateway, so no external network is used.
//
// The flutter test binding is deliberately NOT initialised here: it installs
// HttpOverrides that block real sockets, and Dio needs a real HttpClient to
// reach the loopback server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/colibri_service.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Handler = Future<void> Function(HttpRequest req);

void main() {
  late HttpServer server;
  late String base;
  final handlers = <String, _Handler>{};
  final bodies = <String, Map<String, dynamic>>{};

  Future<void> writeJson(HttpRequest req, Object body, [int status = 200]) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    return Future.value();
  }

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    unawaited(server.forEach((req) async {
      final key = req.uri.path;
      if (req.method == 'POST') {
        final text = await utf8.decodeStream(req);
        bodies[key] = jsonDecode(text) as Map<String, dynamic>;
      }
      final handler = handlers[key];
      if (handler != null) {
        await handler(req);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    }));
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() {
    handlers.clear();
    bodies.clear();
  });

  final svc = ColibriService();

  group('shouldEscalateToCloud half-dose wording', () {
    test('"take half of" escalates via the half-action rule', () {
      expect(ColibriService.shouldEscalateToCloud('Can I take half of it?'),
          isTrue);
    });

    test('"in half" without an action verb does not escalate', () {
      expect(
          ColibriService.shouldEscalateToCloud('the day is in half'), isFalse);
    });
  });

  group('checkHealth', () {
    test('returns [] when the server responds without a data list', () async {
      handlers['/v1/models'] = (req) => writeJson(req, {'models': []});
      final models = await svc.checkHealth(customBaseUrl: '$base/v1');
      expect(models, isEmpty);
    });

    test('returns [] when the request fails', () async {
      final models = await svc.checkHealth(customBaseUrl: '$base/missing');
      expect(models, isEmpty);
    });

    test('lists model ids and remembers the working base url', () async {
      handlers['/v1/models'] = (req) => writeJson(req, {
            'data': [
              {'id': 'olmoe-colibri'},
              {'id': 7},
            ],
          });
      final models = await svc.checkHealth(customBaseUrl: '$base/v1');
      expect(models, ['olmoe-colibri', '7']);
      expect(svc.getDefaultColibriUrl(), '$base/v1');

      // With no custom url, the resolved url is reused.
      final again = await svc.checkHealth();
      expect(again, ['olmoe-colibri', '7']);
    });
  });

  group('completeChat', () {
    test('returns content, token stats and escalation flag', () async {
      handlers['/v1/chat/completions'] = (req) => writeJson(req, {
            'choices': [
              {
                'message': {
                  'content': '${ColibriService.escalateToken} needs cloud',
                },
              },
            ],
            'usage': {'total_tokens': 40},
          });
      final result = await svc.completeChat(
        prompt: 'hello',
        customBaseUrl: '$base/v1',
        model: 'm1',
        systemPrompt: 'SYS',
        temperature: 0.5,
      );
      expect(result['success'], isTrue);
      expect(result['content'], contains('needs cloud'));
      expect(result['model'], 'm1');
      expect(result['totalTokens'], 40);
      expect(result['escalateToCloud'], isTrue);
      expect(result['tokensPerSec'], isA<String>());

      final sent = bodies['/v1/chat/completions']!;
      expect(sent['model'], 'm1');
      expect(sent['temperature'], 0.5);
      expect((sent['messages'] as List).first['content'], 'SYS');
    });

    test('handles empty choices and missing usage', () async {
      handlers['/v1/chat/completions'] =
          (req) => writeJson(req, {'choices': []});
      final result =
          await svc.completeChat(prompt: 'x', customBaseUrl: '$base/v1');
      expect(result['success'], isTrue);
      expect(result['content'], '');
      expect(result['totalTokens'], 0);
      expect(result['tokensPerSec'], '0.0');
      expect(result['escalateToCloud'], isFalse);
      final sent = bodies['/v1/chat/completions']!;
      expect((sent['messages'] as List).first['content'],
          contains('CareConnect Edge Assistant'));
    });

    test('non-200 success status reports an HTTP error', () async {
      handlers['/v1/chat/completions'] =
          (req) => writeJson(req, {'created': true}, 201);
      final result =
          await svc.completeChat(prompt: 'x', customBaseUrl: '$base/v1');
      expect(result['success'], isFalse);
      expect(result['error'], 'Colibri returned HTTP 201');
      expect(result['escalateToCloud'], isFalse);
    });

    test('connection errors are reported, not thrown', () async {
      handlers['/v1/chat/completions'] =
          (req) => writeJson(req, {'error': 'x'}, 500);
      final result =
          await svc.completeChat(prompt: 'x', customBaseUrl: '$base/v1');
      expect(result['success'], isFalse);
      expect(result['error'], startsWith('Colibri connection error'));
    });
  });

  group('queryLocalClinicalAssistant', () {
    test('grounds routine questions with local patient context', () async {
      // Ensure the default url resolves to the loopback server.
      handlers['/v1/models'] = (req) => writeJson(req, {
            'data': [
              {'id': 'olmoe-colibri'},
            ],
          });
      await svc.checkHealth(customBaseUrl: '$base/v1');

      handlers['/v1/chat/completions'] = (req) => writeJson(req, {
            'choices': [
              {
                'message': {'content': 'Your next visit is Monday.'},
              },
            ],
            'usage': {'total_tokens': 5},
          });
      final result = await svc.queryLocalClinicalAssistant(
        question: 'When is my next visit?',
        localPatientData: {'nextVisit': 'Monday'},
      );
      expect(result['success'], isTrue);
      expect(result['content'], 'Your next visit is Monday.');
      final sent = bodies['/v1/chat/completions']!;
      expect(sent['temperature'], 0.2);
      expect((sent['messages'] as List).first['content'],
          contains('[LOCAL PATIENT CONTEXT]'));
    });

    test('omits context block when no patient data is given', () async {
      handlers['/v1/chat/completions'] = (req) => writeJson(req, {
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          });
      final result =
          await svc.queryLocalClinicalAssistant(question: 'Hello there');
      expect(result['content'], 'ok');
      final sent = bodies['/v1/chat/completions']!;
      expect((sent['messages'] as List).first['content'],
          isNot(contains('[LOCAL PATIENT CONTEXT]')));
    });
  });
}
