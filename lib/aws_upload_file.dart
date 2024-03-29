library aws_upload_file;

import 'dart:async';

import 'package:aws_upload_file/src/aws_upload_manager.dart';
import 'package:aws_upload_file/src/constants.dart';
import 'package:aws_upload_file/src/entities/exceptions.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:aws_upload_file/src/entities/exceptions.dart';

// TODO add documentation to every public method
class AwsUploadFile {
  late int _chunkSize;
  SharedPreferences? prefs;
  Dio? dio;

  bool _initialized = false;
  AwsUploadManager? _currentManager;
  StreamSubscription? _currentSubscription;

  bool get isInitialized => _initialized;
  int get chunkSize => _chunkSize;

  AwsUploadFile({
    this.prefs,
    this.dio,
  });

  Future<void> config({int chunkSize = defaultChunkSize}) async {
    if (!_initialized) {
      dio ??= Dio();
      prefs ??= await SharedPreferences.getInstance();
      _chunkSize = chunkSize;
      _initialized = true;
    }
  }

  Future<ValueStream<double>> uploadFile(
    XFile file, {
    required int fileSize,
    required List<String> partUploadUrls,
    required String completeUploadUrl,
  }) async {
    if (!_initialized) {
      throw const UploadUninitializedException();
    }

    if (hasUploadInProgress()) {
      throw const UploadAlreadyInProgressException();
    }

    _currentManager = AwsUploadManager.fromUploadUrls(
      dio: dio!,
      sharedPreferences: prefs!,
      chunkSize: _chunkSize,
      partUploadUrls: partUploadUrls,
      completeUploadUrl: completeUploadUrl,
      file: file,
      fileSize: fileSize,
      onDone: cancelUpload,
    );

    await _storeManager();

    _currentManager!.startUpload();

    _subscribeToChunkCompletion();

    return _currentManager!.progressStream;
  }

  ValueStream<double> resumeUploadFile() {
    if (!_initialized) {
      throw const UploadUninitializedException();
    }
    if (!hasUploadInProgress()) {
      throw const UploadNotInProgressException();
    }

    _currentManager ??= _retrieveManager();

    _subscribeToChunkCompletion();

    _currentManager!.resumeUpload();

    return _currentManager!.progressStream;
  }

  Future<void> cancelUpload() async {
    if (!_initialized) {
      throw const UploadUninitializedException();
    }

    if (!hasUploadInProgress()) {
      throw const UploadNotInProgressException();
    }

    _currentManager ??= _retrieveManager();

    _currentSubscription?.cancel();
    _currentManager?.cancelUpload();
    _cancelStoredManager();
    _currentSubscription = null;
    _currentManager = null;
  }

  Future<void> _storeManager() async {
    final result = await prefs!
        .setString(prefsManagerKey, _currentManager?.toJson() ?? "");
    if (!result) {
      debugPrint(
        "AWS-UPLOAD-FILE: upload status not saved in shared preferences",
      );
    }
  }

  Future<void> _cancelStoredManager() async {
    final result = await prefs!.remove(prefsManagerKey);
    if (!result) {
      debugPrint(
        "AWS-UPLOAD-FILE: upload status not deleted in shared preferences",
      );
    }
  }

  AwsUploadManager? _retrieveManager() {
    final json = _getStoredManagerJson();
    if (json == null) return null;
    return AwsUploadManager.fromJson(
      json,
      dio: dio!,
      sharedPreferences: prefs!,
      onDone: cancelUpload,
    );
  }

  void _subscribeToChunkCompletion() {
    _currentSubscription?.cancel();
    // every time a request is completed, save the current manager status to the store
    _currentSubscription = _currentManager?.chunkCompletedStream.listen(
      (i) {
        debugPrint("AWS - chunk completed $i");
        _storeManager();
      },
      onDone: _cancelStoredManager,
    );
  }

  bool hasUploadInProgress() {
    return _getStoredManagerJson() != null;
  }

  String? _getStoredManagerJson() {
    return prefs!.getString(prefsManagerKey);
  }
}
