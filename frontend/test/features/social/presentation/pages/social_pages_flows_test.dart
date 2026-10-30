// Flow tests for the social pages backed by a MockClient: main feed (posts,
// comments, new post), friend requests (accept / reject), user search
// (search / add) and the contacts list for caregivers and patients.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/comment_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/friend_requests_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/main_feed_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/my_friend_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/new_post_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/search_user_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

Map<String, dynamic> _post(int id, String content) => {
      'id': id,
      'userId': 1,
      'content': content,
      'imageUrl': null,
      'createdAt': '2026-10-01T10:00:00',
      'commentCount': 2,
      'username': 'Poster $id',
    };

/// Mutable backend shared by the tests.
class _Backend {
  int status = 200;
  int postStatus = 201;
  bool emptyRequests = false;
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.Request request) async {
    final p = request.url.path;
    calls.add('${request.method} $p');
    if (status != 200 && request.method == 'GET') {
      return http.Response('{"error":"x"}', status);
    }
    if (p.endsWith('/feed/friends-feed')) {
      return http.Response(jsonEncode([_post(1, 'First post')]), 200);
    }
    if (p.endsWith('/feed/create')) {
      return http.Response(jsonEncode(_post(2, 'Fresh post')), postStatus);
    }
    if (p.contains('/comments/post/')) {
      if (request.method == 'POST') return http.Response('{}', postStatus);
      return http.Response(
        jsonEncode([
          {
            'id': 5,
            'userId': 2,
            'postId': 1,
            'content': 'Nice post',
            'username': 'Commenter',
            'createdAt': '2026-10-02T09:30:00',
          },
        ]),
        200,
      );
    }
    if (p.contains('/friends/requests/')) {
      return http.Response(
        jsonEncode(emptyRequests
            ? []
            : [
                {
                  'id': 9,
                  'fromUserId': 3,
                  'toUserId': 1,
                  'fromUsername': 'Bob',
                  'from_username': 'Bob',
                },
              ]),
        200,
      );
    }
    if (p.endsWith('/friends/accept') || p.endsWith('/friends/reject')) {
      emptyRequests = true;
      return http.Response('{}', postStatus == 201 ? 200 : postStatus);
    }
    if (p.contains('/users/search') || p.contains('search')) {
      return http.Response(
        jsonEncode([
          {'id': 4, 'name': 'Carol', 'email': 'carol@example.com'},
        ]),
        200,
      );
    }
    if (p.contains('/friends/request')) {
      return http.Response('{}', postStatus);
    }
    if (p.contains('/caregivers/') && p.endsWith('/patients')) {
      return http.Response(
        jsonEncode([
          {'link': null, 'patient': null},
          {
            'link': {'patientUserId': 2},
            'patient': {
              'firstName': 'Pat',
              'lastName': 'Ient',
              'email': 'pat@example.com',
            },
          },
        ]),
        200,
      );
    }
    if (p.contains('/caregiver-patient-links/patients/')) {
      return http.Response(
        jsonEncode([
          {'caregiverUserId': 5, 'patientMessagingEnabled': false},
          {
            'caregiverUserId': 6,
            'caregiverName': 'Cara Giver',
            'caregiverEmail': 'cara@example.com',
          },
        ]),
        200,
      );
    }
    return http.Response('[]', 200);
  }
}

late _Backend _b;

Widget _app(Widget home, {String role = 'PATIENT', int? caregiverId}) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
      mockUser: MockUser(id: 1, role: role, caregiverId: caregiverId),
    ),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

Future<void> _run(Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(_b.handle));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _b = _Backend();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
    ApiService.debugSetHttpClient(MockClient(_b.handle));
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  testWidgets('feed loads posts, opens comments and adds a comment',
      (tester) async {
    await _run(() async {
      await tester.pumpWidget(_app(const MainFeedScreen(userId: 1)));
      await _settle(tester);
      expect(find.text('First post'), findsOneWidget);

      // Silent poll with identical data keeps the list.
      await tester.pump(const Duration(seconds: 10));
      await _settle(tester);

      await tester.tap(find.text('First post'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentScreen), findsOneWidget);
      expect(find.text('Nice post'), findsOneWidget);
      expect(find.text('Commenter'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'My comment');
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(_b.calls.where((c) => c.startsWith('POST')), hasLength(1));
    });
  });

  testWidgets('feed error shows the load error snackbar', (tester) async {
    _b.status = 500;
    await _run(() async {
      await tester.pumpWidget(_app(const MainFeedScreen(userId: 1)));
      await _settle(tester);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  testWidgets('creating a post inserts it at the top of the feed',
      (tester) async {
    await _run(() async {
      await tester.pumpWidget(_app(const MainFeedScreen(userId: 1)));
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();
      expect(find.byType(NewPostScreen), findsOneWidget);

      // Empty content is rejected first.
      await tester.tap(find.text('Post'));
      await tester.pump();
      expect(find.text('Post content cannot be empty'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Fresh post');
      await tester.tap(find.text('Post'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(NewPostScreen), findsNothing);
      expect(find.text('Fresh post'), findsOneWidget);
    });
  });

  testWidgets('new post failure shows the server error', (tester) async {
    _b.postStatus = 400;
    await _run(() async {
      await tester.pumpWidget(_app(const NewPostScreen()));
      await tester.enterText(find.byType(TextFormField), 'Bad post');
      await tester.tap(find.text('Post'));
      await _settle(tester);
      expect(find.textContaining('Error:'), findsOneWidget);
    });
  });

  testWidgets('comments: load error, empty submit and failed submit',
      (tester) async {
    _b.status = 500;
    _b.postStatus = 400;
    await _run(() async {
      await tester.pumpWidget(_app(const CommentScreen(postId: 1)));
      await _settle(tester);
      expect(find.textContaining('Failed to load comments'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(TextField)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.text('User not loaded or comment empty'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(TextField)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Will fail');
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(find.text('Failed to add comment'), findsOneWidget);
    });
  });

  testWidgets('friend requests: accept, reject and open friends',
      (tester) async {
    await _run(() async {
      await tester.pumpWidget(_app(const FriendRequestsScreen()));
      await _settle(tester);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Request ID: 9'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await _settle(tester);
      expect(find.text('Request accepted'), findsOneWidget);
      expect(find.text('No pending requests'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.group));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(MyFriendsScreen), findsOneWidget);
    });
  });

  testWidgets('friend requests: reject and failures', (tester) async {
    await _run(() async {
      await tester.pumpWidget(_app(const FriendRequestsScreen()));
      await _settle(tester);
      await tester.tap(find.text('Reject'));
      await _settle(tester);
      expect(find.text('Request rejected'), findsOneWidget);
    });
  });

  testWidgets('friend requests: accept/reject failures and load failure',
      (tester) async {
    _b.postStatus = 500;
    await _run(() async {
      await tester.pumpWidget(_app(const FriendRequestsScreen()));
      await _settle(tester);
      await tester.tap(find.text('Accept'));
      await _settle(tester);
      expect(find.text('Failed to accept request'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.text('Bob')))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await _settle(tester);
      expect(find.text('Failed to reject request'), findsWidgets);
    });

    _b.status = 500;
    await _run(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(const FriendRequestsScreen()));
      await _settle(tester);
      expect(find.text('Failed to load requests'), findsOneWidget);
    });
  });

  testWidgets('search finds users and sends a friend request',
      (tester) async {
    await tester.pumpWidget(_app(const SearchUserScreen()));
    await tester.enterText(find.byType(TextField), 'carol');
    await tester.tap(find.byIcon(Icons.search));
    await _settle(tester);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('carol@example.com'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await _settle(tester);
    expect(find.text('Friend request sent'), findsOneWidget);
  });

  testWidgets('search and request failures show snackbars', (tester) async {
    _b.postStatus = 400;
    await tester.pumpWidget(_app(const SearchUserScreen()));
    await tester.enterText(find.byType(TextField), 'carol');
    await tester.tap(find.byIcon(Icons.search));
    await _settle(tester);
    await tester.tap(find.text('Add'));
    await _settle(tester);
    expect(find.text('Request failed'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.text('Carol')))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    _b.status = 500;
    await tester.tap(find.byIcon(Icons.search));
    await _settle(tester);
    expect(find.text('Search failed'), findsOneWidget);
  });

  testWidgets('caregiver contacts list patients and open a chat',
      (tester) async {
    await _run(() async {
      await tester.pumpWidget(
        _app(const MyFriendsScreen(), role: 'CAREGIVER', caregiverId: 7),
      );
      await _settle(tester);
      expect(find.text('Pat Ient'), findsOneWidget);
      expect(find.text('Patient · pat@example.com'), findsOneWidget);
    });
  });

  testWidgets('patient contacts list messaging-enabled caregivers',
      (tester) async {
    await _run(() async {
      await tester.pumpWidget(_app(const MyFriendsScreen()));
      await _settle(tester);
      expect(find.text('Cara Giver'), findsOneWidget);
      await tester.tap(find.text('Cara Giver'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      // Leave the chat room before the test ends so its timers stop.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('contacts load failure shows a snackbar', (tester) async {
    _b.status = 500;
    await _run(() async {
      await tester.pumpWidget(_app(const MyFriendsScreen()));
      await _settle(tester);
      expect(find.textContaining('Failed to load contacts'), findsOneWidget);
    });
  });
}
