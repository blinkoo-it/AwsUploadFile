library aws_upload_file;

import 'dart:async';

import 'package:aws_upload_file/src/aws_upload_manager.dart';
import 'package:aws_upload_file/src/entities/exceptions.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:aws_upload_file/src/entities/exceptions.dart';

const _defaultChunkSize = 5 * 1024 * 1024;
const _prefsManagerKey = "awsCurrentUploadManager";

// TODO add documentation to every public method
class AwsUploadFile {
  late SharedPreferences _prefs;
  late int _chunkSize;

  bool _initialized = false;
  AwsUploadManager? currentManager;
  StreamSubscription? currentSubscription;
  AwsUploadFile();

  Future<void> config({int chunkSize = _defaultChunkSize}) async {
    if (!_initialized) {
      _initialized = true;
      _chunkSize = chunkSize;
      _prefs = await SharedPreferences.getInstance();
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

    currentManager = AwsUploadManager.fromUploadUrls(
      chunkSize: _chunkSize,
      partUploadUrls: partUploadUrls,
      completeUploadUrl: completeUploadUrl,
      file: file,
      fileSize: fileSize,
      onDone: cancelUpload,
    );

    await _storeManager();

    currentManager!.startUpload();

    _subscribeToChunkCompletion();

    return currentManager!.progressStream;
  }

  ValueStream<double> resumeUploadFile() {
    if (!_initialized) {
      throw const UploadUninitializedException();
    }
    if (!hasUploadInProgress()) {
      throw const UploadNotInProgressException();
    }

    currentManager ??= _retrieveManager();

    _subscribeToChunkCompletion();

    currentManager!.resumeUpload();

    return currentManager!.progressStream;
  }

  Future<void> cancelUpload() async {
    if (!_initialized) {
      throw const UploadUninitializedException();
    }

    if (!hasUploadInProgress()) {
      throw const UploadNotInProgressException();
    }

    currentManager ??= _retrieveManager();

    currentSubscription?.cancel();
    currentManager?.cancelUpload();
    _cancelStoredManager();
    currentSubscription = null;
    currentManager = null;
  }

  Future<void> _storeManager() async {
    final result = await _prefs.setString(
        _prefsManagerKey, currentManager?.toJson() ?? "");
    if (!result) {
      debugPrint(
        "AWS-UPLOAD-FILE: upload status not saved in shared preferences",
      );
    }
  }

  Future<void> _cancelStoredManager() async {
    final result = await _prefs.remove(_prefsManagerKey);
    if (!result) {
      debugPrint(
        "AWS-UPLOAD-FILE: upload status not deleted in shared preferences",
      );
    }
  }

  AwsUploadManager? _retrieveManager() {
    final json = _getStoredManagerJson();
    if (json == null) return null;
    return AwsUploadManager.fromJson(json);
  }

  void _subscribeToChunkCompletion() {
    currentSubscription?.cancel();
    // every time a request is completed, save the current manager status to the store
    currentSubscription = currentManager?.chunkCompletedStream.listen(
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
    return _prefs.getString(_prefsManagerKey);
  }
}
