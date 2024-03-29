import 'dart:async';
import 'dart:typed_data';

import 'package:aws_upload_file/aws_upload_file.dart';
import 'package:aws_upload_file/src/aws_upload_manager.dart';
import 'package:aws_upload_file/src/constants.dart';
import 'package:aws_upload_file/src/entities/complete_multipart_upload.dart';
import 'package:aws_upload_file/src/entities/part_upload.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aws_upload_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Dio>(
    as: #MockDio,
    onMissingStub: OnMissingStub.returnDefault,
  ),
  MockSpec<SharedPreferences>(
    as: #MockSharedPreferences,
    onMissingStub: OnMissingStub.returnDefault,
  ),
  // this mock is generated wrong https://github.com/dart-lang/mockito/issues/529
  // fix the import in the generated file with import 'package:cross_file/cross_file.dart'
  // to let it work
  MockSpec<XFile>(
    as: #MockXFile,
    onMissingStub: OnMissingStub.returnDefault,
  ),
  MockSpec<RequestOptions>(
    as: #MockRequestOptions,
    onMissingStub: OnMissingStub.returnDefault,
  ),
])
void main() {
  late MockDio dio;
  late AwsUploadFile uploader;
  late MockSharedPreferences sharedPreferences;
  String? sharedPreferencesStorage;

  MockXFile createXFile({
    bool throwError = false,
    String filePath = "filePath.mp4",
  }) {
    final MockXFile xFile = MockXFile();
    when(xFile.path).thenReturn(filePath);
    if (throwError) {
      when(xFile.openRead(any, any)).thenThrow(
        Exception("random error"),
      );
    } else {
      when(xFile.openRead(any, any)).thenAnswer((realInvocation) async* {
        final int start = realInvocation.positionalArguments[0];
        final int end = realInvocation.positionalArguments[1];
        yield Uint8List(end - start);
      });
    }
    return xFile;
  }

  Function mockUploadPartRequest({
    required String partUrl,
    required int partSize,
    required String etag,
    int responseCode = 200,
  }) {
    dynamic getUploadPartMockedRequest() => dio.put(
          partUrl,
          options: anyNamed("options"),
          cancelToken: anyNamed("cancelToken"),
          data: anyNamed("data"),
          onSendProgress: anyNamed("onSendProgress"),
        );

    when(getUploadPartMockedRequest()).thenAnswer((realInvocation) async {
      final onSendProgress =
          realInvocation.namedArguments[const Symbol("onSendProgress")];

      onSendProgress!(partSize ~/ 2, partSize);
      await Future.delayed(const Duration(milliseconds: 5));
      onSendProgress(partSize, partSize);

      return Response(
        requestOptions: MockRequestOptions(),
        headers: Headers()..add("etag", etag),
        statusCode: responseCode,
      );
    });

    return getUploadPartMockedRequest;
  }

  void mockUploadPartRequestError({
    required String partUrl,
    required int partSize,
    int? responseCode,
    Exception? exception,
  }) {
    if (exception == null) {
      mockUploadPartRequest(
        partUrl: partUrl,
        partSize: partSize,
        etag: "",
        responseCode: responseCode!,
      );
      return;
    }
    when(
      dio.put(
        partUrl,
        options: anyNamed("options"),
        cancelToken: anyNamed("cancelToken"),
        data: anyNamed("data"),
        onSendProgress: anyNamed("onSendProgress"),
      ),
    ).thenThrow(exception);
  }

  dynamic mockCompleteUploadRequest({
    required String completeUrl,
    int responseCode = 200,
  }) {
    dynamic getCompleteUploadMockedRequest() => dio.post(
          completeUrl,
          options: anyNamed("options"),
          cancelToken: anyNamed("cancelToken"),
          data: captureAnyNamed("data"),
        );
    when(getCompleteUploadMockedRequest()).thenAnswer((realInvocation) async {
      return Response(
        requestOptions: MockRequestOptions(),
        statusCode: responseCode,
      );
    });

    return getCompleteUploadMockedRequest;
  }

  setUp(() async {
    dio = MockDio();
    sharedPreferences = MockSharedPreferences();
    sharedPreferencesStorage = null;
    uploader = AwsUploadFile(dio: dio, prefs: sharedPreferences);

    // stab SharedPreferences
    when(sharedPreferences.getString(prefsManagerKey)).thenAnswer(
      (realInvocation) => sharedPreferencesStorage,
    );

    when(sharedPreferences.setString(prefsManagerKey, any)).thenAnswer(
      (realInvocation) async {
        sharedPreferencesStorage = realInvocation.positionalArguments[1];
        return true;
      },
    );

    when(sharedPreferences.remove(prefsManagerKey)).thenAnswer(
      (realInvocation) async {
        sharedPreferencesStorage = null;
        return true;
      },
    );
  });

  group(
    "Config",
    () {
      test(
        "Config works",
        () async {
          await uploader.config();

          expect(uploader.isInitialized, isTrue);
          expect(uploader.chunkSize, defaultChunkSize);
        },
      );

      test(
        "Config works with custom chunkSize",
        () async {
          await uploader.config(chunkSize: 10);

          expect(uploader.isInitialized, isTrue);
          expect(uploader.chunkSize, 10);
        },
      );

      test(
        "Config after initialize does nothing",
        () async {
          await uploader.config();
          await uploader.config(chunkSize: 10);

          expect(uploader.isInitialized, isTrue);
          expect(uploader.chunkSize, defaultChunkSize);
        },
      );
    },
  );

  group(
    "Upload file",
    () {
      test(
        "Upload without init fails",
        () async {
          expect(
            () => uploader.uploadFile(
              MockXFile(),
              fileSize: 10,
              partUploadUrls: [""],
              completeUploadUrl: "",
            ),
            throwsA(const TypeMatcher<UploadUninitializedException>()),
          );
        },
      );

      test(
        "Upload with already running upload fails",
        () async {
          sharedPreferencesStorage = "something";
          await uploader.config();

          expect(
            () => uploader.uploadFile(
              MockXFile(),
              fileSize: 10,
              partUploadUrls: [""],
              completeUploadUrl: "",
            ),
            throwsA(const TypeMatcher<UploadAlreadyInProgressException>()),
          );
        },
      );

      test(
        "Upload single request works",
        () async {
          final XFile xFile = createXFile();

          final part1Call = mockUploadPartRequest(
            partUrl: "url1",
            partSize: 10,
            etag: "etag1",
          );

          final completeUploadCall = mockCompleteUploadRequest(
            completeUrl: "completeUrl",
          );

          await uploader.config();

          ValueStream<double> stream = await uploader.uploadFile(
            xFile,
            fileSize: 10,
            partUploadUrls: ["url1"],
            completeUploadUrl: "completeUrl",
          );

          double finalValue = await stream.last;

          expect(finalValue, 1.0);
          expect(sharedPreferencesStorage, isNull);
          verify(part1Call()).called(1);
          final completeUploadResult = verify(completeUploadCall());
          completeUploadResult.called(1);
          expect(
            completeUploadResult.captured.first,
            CompleteMultipartUploadBody(
              etags: {1: "etag1"},
            ).toXML(),
          );
        },
      );

      test(
        "Upload multiple requests works",
        () async {
          final XFile xFile = createXFile();

          final part1Call = mockUploadPartRequest(
            partUrl: "url1",
            partSize: 10,
            etag: "etag1",
          );

          final part2Call = mockUploadPartRequest(
            partUrl: "url2",
            partSize: 10,
            etag: "etag2",
          );

          final part3Call = mockUploadPartRequest(
            partUrl: "url3",
            partSize: 10,
            etag: "etag3",
          );

          final part4Call = mockUploadPartRequest(
            partUrl: "url4",
            partSize: 10,
            etag: "etag4",
          );

          final completeUploadCall = mockCompleteUploadRequest(
            completeUrl: "completeUrl",
          );

          await uploader.config(chunkSize: 10);

          ValueStream<double> stream = await uploader.uploadFile(
            xFile,
            fileSize: 40,
            partUploadUrls: ["url1", "url2", "url3", "url4"],
            completeUploadUrl: "completeUrl",
          );

          final List<double> emissions = await stream.toList();

          expect(emissions,
              [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]);
          expect(sharedPreferencesStorage, isNull);
          verify(part1Call()).called(1);
          verify(part2Call()).called(1);
          verify(part3Call()).called(1);
          verify(part4Call()).called(1);
          final completeUploadResult = verify(completeUploadCall());
          completeUploadResult.called(1);
          expect(
            completeUploadResult.captured.first,
            CompleteMultipartUploadBody(
              etags: {1: "etag1", 2: "etag2", 3: "etag3", 4: "etag4"},
            ).toXML(),
          );
        },
      );

      test(
        "Upload part request fail: wrong status code",
        () async {
          final XFile xFile = createXFile();

          mockUploadPartRequestError(
            partUrl: "url1",
            partSize: 10,
            responseCode: 401,
          );

          await uploader.config();

          final Completer<void> synchronizer = Completer();
          ValueStream<double> stream = await uploader.uploadFile(
            xFile,
            fileSize: 10,
            partUploadUrls: ["url1"],
            completeUploadUrl: "completeUrl",
          );
          stream.listen((event) {}, onError: (e) {
            expect(e, isA<UploadPartResponseException>());
            synchronizer.complete();
          });

          await synchronizer.future;
          expect(sharedPreferencesStorage, isNotNull);
        },
      );

      test(
        "Upload part request fail: communication error",
        () async {
          final XFile xFile = createXFile();

          mockUploadPartRequestError(
            partUrl: "url1",
            partSize: 10,
            exception: Exception("random error"),
          );

          await uploader.config();

          final Completer<void> synchronizer = Completer();
          ValueStream<double> stream = await uploader.uploadFile(
            xFile,
            fileSize: 10,
            partUploadUrls: ["url1"],
            completeUploadUrl: "completeUrl",
          );
          stream.listen((event) {}, onError: (e) {
            synchronizer.complete();
            expect(e, isA<UploadPartResponseException>());
          });

          await synchronizer.future;
          expect(sharedPreferencesStorage, isNotNull);
        },
      );

      test(
        "Upload part request fail: read file",
        () async {
          final XFile xFile = createXFile(throwError: true);

          mockUploadPartRequest(
            partUrl: "url1",
            partSize: 10,
            etag: "etag1",
          );

          await uploader.config();

          final Completer<void> synchronizer = Completer();
          ValueStream<double> stream = await uploader.uploadFile(
            xFile,
            fileSize: 10,
            partUploadUrls: ["url1"],
            completeUploadUrl: "completeUrl",
          );
          stream.listen((event) {}, onError: (e) {
            synchronizer.complete();
            expect(e, isA<UploadFileReadException>());
          });

          await synchronizer.future;
          expect(sharedPreferencesStorage, isNotNull);
        },
      );
    },
  );

  group(
    "Resume upload",
    () {
      test(
        "Resume without init fails",
        () async {
          expect(
            () => uploader.resumeUploadFile(),
            throwsA(const TypeMatcher<UploadUninitializedException>()),
          );
        },
      );

      test(
        "Resume without already running upload fails",
        () async {
          await uploader.config();

          expect(
            () => uploader.resumeUploadFile(),
            throwsA(const TypeMatcher<UploadNotInProgressException>()),
          );
        },
      );

      test(
        // we can't test resume working because resume regenerates the xFile from the fakePath
        "Resume after first part request",
        () async {
          final XFile xFile = createXFile();

          await uploader.config(chunkSize: 10);

          sharedPreferencesStorage = AwsUploadManager(
            dio: dio,
            sharedPreferences: sharedPreferences,
            chunkSize: 10,
            partUploads: [
              PartUpload(
                url: "url1",
                number: 1,
                size: 10,
                completed: true,
                etag: "etag1",
              ),
              PartUpload(
                url: "url2",
                number: 2,
                size: 5,
              ),
            ],
            completeUploadUrl: "completeUploadUrl",
            file: xFile,
            fileSize: 15,
          ).toJson();

          final Completer<void> synchronizer = Completer();
          final stream = uploader.resumeUploadFile()
            ..listen(
              (event) {
                expect(event, 2 / 3);
              },
              onError: (error) {
                synchronizer.complete();
                expect(error.toString().contains("part 2"), isTrue);
              },
            );
          if (!synchronizer.isCompleted) await synchronizer.future;

          expect(stream.value, 2 / 3);
        },
      );

      test(
        // we can't test resume working because resume regenerates the xFile from the fakePath
        "Resume with only complete request",
        () async {
          final XFile xFile = createXFile();
          await uploader.config(chunkSize: 10);

          sharedPreferencesStorage = AwsUploadManager(
            dio: dio,
            sharedPreferences: sharedPreferences,
            chunkSize: 10,
            partUploads: [
              PartUpload(
                url: "url1",
                number: 1,
                size: 10,
                completed: true,
                etag: "etag1",
              ),
              PartUpload(
                url: "url2",
                number: 2,
                size: 5,
                completed: true,
                etag: "etag2",
              ),
            ],
            completeUploadUrl: "completeUploadUrl",
            file: xFile,
            fileSize: 15,
          ).toJson();

          final part1Call = mockUploadPartRequest(
            partUrl: "url1",
            partSize: 10,
            etag: "etag1",
          );

          final part2Call = mockUploadPartRequest(
            partUrl: "url2",
            partSize: 5,
            etag: "etag2",
          );

          final completeUploadCall =
              mockCompleteUploadRequest(completeUrl: "completeUploadUrl");

          final stream = uploader.resumeUploadFile();
          final emissions = await stream.toList();

          expect(emissions, [1.0]);
          verifyNever(part1Call());
          verifyNever(part2Call());
          final completeUploadResult = verify(completeUploadCall());
          completeUploadResult.called(1);
          expect(
            completeUploadResult.captured.first,
            CompleteMultipartUploadBody(
              etags: {1: "etag1", 2: "etag2"},
            ).toXML(),
          );
        },
      );
    },
  );

  group(
    "Cancel upload",
    () {
      test(
        "Cancel without init fails",
        () async {
          expect(
            () => uploader.cancelUpload(),
            throwsA(const TypeMatcher<UploadUninitializedException>()),
          );
        },
      );

      test(
        "Cancel without already running upload fails",
        () async {
          await uploader.config();

          expect(
            () => uploader.cancelUpload(),
            throwsA(const TypeMatcher<UploadNotInProgressException>()),
          );
        },
      );

      test(
        "Cancel current request works",
        () async {
          final XFile xFile = createXFile();
          await uploader.config(chunkSize: 10);

          sharedPreferencesStorage = AwsUploadManager(
            dio: dio,
            sharedPreferences: sharedPreferences,
            chunkSize: 10,
            partUploads: [
              PartUpload(
                url: "url1",
                number: 1,
                size: 10,
                completed: true,
                etag: "etag1",
              ),
              PartUpload(
                url: "url2",
                number: 2,
                size: 5,
                completed: false,
              ),
            ],
            completeUploadUrl: "completeUploadUrl",
            file: xFile,
            fileSize: 15,
          ).toJson();

          final part2Call = mockUploadPartRequest(
            partUrl: "url2",
            partSize: 5,
            etag: "etag2",
            responseCode: 500,
          );

          final completeUploadCall =
              mockCompleteUploadRequest(completeUrl: "completeUploadUrl");

          final Completer<void> synchronizer = Completer();

          uploader.resumeUploadFile().listen(
            (event) {},
            onDone: () {
              synchronizer.complete();
            },
          );
          await uploader.cancelUpload();
          if (!synchronizer.isCompleted) await synchronizer.future;

          verifyNever(part2Call());
          verifyNever(completeUploadCall());
        },
      );
    },
  );
}
