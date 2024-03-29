// ignore_for_file: invalid_use_of_protected_member

import 'package:aws_upload_file/aws_upload_file.dart';
import 'package:aws_upload_file/src/aws_upload_manager.dart';
import 'package:aws_upload_file/src/constants.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
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
  )
])
void main() {
  late MockDio dio;
  late AwsUploadFile uploader;
  late MockSharedPreferences sharedPreferences;
  String? sharedPreferencesStorage;

  setUp(() async {
    dio = MockDio();
    sharedPreferences = MockSharedPreferences();
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
    "Resume upload",
    () {},
  );

  group(
    "Cancel upload",
    () {},
  );
}
