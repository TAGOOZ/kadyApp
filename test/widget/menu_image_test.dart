// ignore_for_file: override_on_non_overriding_member
// MenuItemImage — placeholder when imageUrl is null/empty (no Unsplash 503),
// otherwise CachedNetworkImage with real Storage URL. Product name shown in
// placeholder for 180 (detail) so image is product-related.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/ui/menu/widgets/menu_item_image.dart';

// Fake HttpClient that returns 1x1 transparent PNG for any URL — avoids
// "HttpClient 400" in TestWidgetsFlutterBinding.
class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _FakeHttpRequest();
  @override
  void close({bool force = false}) {}
}

class _FakeHttpRequest implements HttpClientRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse();
  @override
  HttpHeaders get headers => _FakeHttpHeaders();
  @override
  String get method => 'GET';
  @override
  Uri get uri => Uri.parse('https://example.com/image.png');
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponse implements HttpClientResponse {
  static final Uint8List _png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=');
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _png.length;
  @override
  int get headersContentLength => _png.length;
  @override
  HttpHeaders get headers => _FakeHttpHeaders();
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => true;
  @override
  String get reasonPhrase => 'OK';
  @override
  List<Cookie> get cookies => const [];
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  X509Certificate? get certificate => null;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) async => this;
  @override
  Future<Socket> detachSocket() => throw UnimplementedError();
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) async => null;
  @override
  Future close() async {}
  @override
  Future get done => Future.value();
  @override
  bool get autoUncompress => false;
  @override
  set autoUncompress(bool v) {}
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  // Stream<Uint8List> delegation
  Stream<Uint8List> get _stream => Stream<Uint8List>.value(_png);
  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


const _nullImageItem = MenuItem(
  id: '1',
  slug: 'latte',
  nameAr: 'لاتيه',
  nameEn: 'Latte',
  descAr: '',
  descEn: '',
  priceEgp: 45,
  isAvailable: true,
  categorySlug: 'espresso',
  imageUrl: null,
);

// Use data URI for test — no HttpClient needed (avoids 400 in TestWidgetsFlutterBinding)
const _realImageItem = MenuItem(
  id: '2',
  slug: 'cheesecake',
  nameAr: 'تشيز كيك',
  nameEn: 'Cheesecake',
  descAr: '',
  descEn: '',
  priceEgp: 80,
  isAvailable: true,
  categorySlug: 'desserts',
  imageUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
);

const _emptyImageItem = MenuItem(
  id: '3',
  slug: 'empty',
  nameAr: 'فارغ',
  nameEn: 'Empty',
  descAr: '',
  descEn: '',
  priceEgp: 10,
  isAvailable: true,
  categorySlug: 'waffle',
  imageUrl: '',
);

void main() {
  testWidgets('null imageUrl renders placeholder without network (fixes WebGL), no label for 72',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: _nullImageItem, width: 72, height: 72),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(MenuPhotoPlaceholder), findsOneWidget);
    expect(find.text('لاتيه'), findsNothing);
    expect(find.text('☕'), findsOneWidget);
  });

  testWidgets('real imageUrl renders CachedNetworkImage with that URL',
      (tester) async {
    HttpOverrides.global = _FakeHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: _realImageItem, width: 72, height: 72),
        ),
      ),
    );

    final finder = find.byType(CachedNetworkImage);
    expect(finder, findsOneWidget);
    final widget = tester.widget<CachedNetworkImage>(finder);
    expect(widget.imageUrl, _realImageItem.imageUrl);
    // CachedNetworkImage errorWidget is MenuPhotoPlaceholder — don't assert
    // absence; verify the image widget is wired correctly. Pump to allow
    // fake HttpClient to complete without throwing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('empty imageUrl falls back to placeholder (not Unsplash) for 72', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: _emptyImageItem, width: 72, height: 72),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(MenuPhotoPlaceholder), findsOneWidget);
    expect(find.text('فارغ'), findsNothing);
  });

  testWidgets('MenuItemImage clips with radius and keeps placeholder fallback',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(
            item: _nullImageItem,
            width: double.infinity,
            height: 180,
            radius: 16,
          ),
        ),
      ),
    );
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(16));
    expect(find.byType(MenuPhotoPlaceholder), findsOneWidget);
  });

  testWidgets('winter-specials null still shows placeholder (no Unsplash) for 72',
      (tester) async {
    const winterItem = MenuItem(
      id: 'w',
      slug: 'sahlab',
      nameAr: 'سحلب',
      nameEn: 'Sahlab',
      descAr: '',
      descEn: '',
      priceEgp: 70,
      isAvailable: true,
      categorySlug: 'winter-specials',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: winterItem, width: 72, height: 72),
        ),
      ),
    );
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(MenuPhotoPlaceholder), findsOneWidget);
    expect(find.text('سحلب'), findsNothing);
  });

  testWidgets('detail 180 shows placeholder with product name label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: _nullImageItem, width: double.infinity, height: 180),
        ),
      ),
    );
    expect(find.byType(MenuPhotoPlaceholder), findsOneWidget);
    expect(find.text('لاتيه'), findsOneWidget);
  });
}
