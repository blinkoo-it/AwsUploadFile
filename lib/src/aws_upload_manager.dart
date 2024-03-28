import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aws_upload_file/src/entities/complete_multipart_upload.dart';
import 'package:aws_upload_file/src/entities/exceptions.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import 'package:aws_upload_file/src/entities/part_upload.dart';

class AwsUploadManager {
  final int chunkSize;
  final List<PartUpload> partUploads;
  final String completeUploadUrl;
  final XFile file;
  final int fileSize;
  final void Function()? onDone;

  final BehaviorSubject<Map<int, int>> _progressSubj;
  final BehaviorSubject<int> _chunkCompletedSubj;

  final dio = Dio();

  ValueStream<int> get _progressSizeStream => _progressSubj
      // sum the sent bytes for each part
      .map((map) => map.values.fold(0, (a, b) => a + b))
      .shareValue();

  ValueStream<double> get progressStream => _progressSizeStream
      // calculate percentage of sent bytes
      .map((sum) => sum / fileSize)
      // avoid to emit changes lesser than 0,5%
      .distinct(
        (old, current) => (old - current).abs() < 0.005,
      )
      .shareValue();

  ValueStream<int> get chunkCompletedStream => _chunkCompletedSubj.shareValue();

  AwsUploadManager({
    required this.chunkSize,
    required this.partUploads,
    required this.completeUploadUrl,
    required this.file,
    required this.fileSize,
    this.onDone,
  })  : _progressSubj = BehaviorSubject(),
        _chunkCompletedSubj = BehaviorSubject() {
    _initStreams();
  }

  AwsUploadManager.fromUploadUrls({
    required this.chunkSize,
    required List<String> partUploadUrls,
    required this.completeUploadUrl,
    required this.file,
    required this.fileSize,
    this.onDone,
  })  : partUploads = partUploadUrls.indexed
            .map<PartUpload>((r) => PartUpload(
                  url: r.$2,
                  number: r.$1 + 1,
                  size: r.$1 < partUploadUrls.length - 1
                      ? chunkSize
                      : fileSize % chunkSize,
                ))
            .toList(),
        _progressSubj = BehaviorSubject(),
        _chunkCompletedSubj = BehaviorSubject() {
    _initStreams();
  }

  _initStreams() {
    final Map<int, int> sentSizes = {
      for (PartUpload p in partUploads.where((part) => part.completed))
        p.number: p.size
    };
    _progressSubj.add(sentSizes);
  }

  void startUpload() async {
    // Note: we upload one chunk per time
    try {
      final partsToUpload = partUploads.where((part) => !part.completed);
      for (PartUpload partUpload in partsToUpload) {
        await _uploadChunk(partUpload);
      }
      // upload completed
      await _completeUpload();
    } on BaseAwsUploadFileException catch (e) {
      _progressSubj.addError(e);
    }
  }

  void resumeUpload() {
    try {
      _initStreams();
      startUpload();
    } on BaseAwsUploadFileException catch (e) {
      _progressSubj.addError(e);
    }
  }

  void cancelUpload() {
    try {
      // TODO implement cancel current call
      _closeStreams();
    } on BaseAwsUploadFileException catch (e) {
      _progressSubj.addError(e);
    }
  }

  Future<void> _uploadChunk(PartUpload partUpload) async {
    final int index = partUpload.number - 1;
    final int start = index * chunkSize;
    final int end = start + partUpload.size;

    Uint8List chunkData;
    try {
      chunkData = await _readChunkFile(start, end);
    } catch (e) {
      debugPrint("AWS - error while reading file $e");
      throw UploadFileReadException(e);
    }
    // make call
    // TODO add content-type
    try {
      final response = await dio.put(partUpload.url, data: chunkData,
          onSendProgress: (int sent, int tot) {
        Map<int, int> value;
        if (_progressSubj.hasValue) {
          value = _progressSubj.value;
          value[partUpload.number] = sent;
        } else {
          value = {partUpload.number: sent};
        }
        _progressSubj.add({...value});
      });

      if (response.statusCode != 200) {
        debugPrint("AWS - part upload response code ${response.statusCode}");
        throw UploadPartResponseException(
          "response status code ${response.statusCode}",
        );
      }

      final String etag = response.headers["etag"]!.first;
      partUpload.etag = etag;
      partUpload.completed = true;
      _chunkCompletedSubj.add(partUpload.number);
    } on BaseAwsUploadFileException catch (_) {
      rethrow;
    } catch (e) {
      final String message =
          "error while uploading part ${partUpload.number} - $e";
      debugPrint("AWS - $message");
      throw UploadPartResponseException(message);
    }
  }

  Future<void> _completeUpload() async {
    try {
      final Map<int, String> etags = partUploads
          .asMap()
          .map((key, value) => MapEntry(value.number, value.etag!));
      final body = CompleteMultipartUploadBody(etags: etags);

      final response = await dio.post(
        completeUploadUrl,
        options: Options(
          headers: {'Content-Type': 'application/xml'},
        ),
        data: body.toXML(),
      );
      if (response.statusCode != 200) {
        debugPrint(
            "AWS - complete request response code ${response.statusCode}");
        throw UploadCompleteResponseException(
          "response status code ${response.statusCode}",
        );
      }
      // close streams
      _closeStreams();
    } on BaseAwsUploadFileException catch (_) {
      rethrow;
    } catch (e) {
      final String message = "error on complete upload request - $e";
      debugPrint("AWS - $message");
      throw UploadCompleteResponseException(message);
    }
  }

  void _closeStreams() {
    _chunkCompletedSubj.close();
    _progressSubj.close();
  }

  Future<Uint8List> _readChunkFile(int start, int end) async {
    return file
        .openRead(start, end)
        .transform(
          ScanStreamTransformer(
            (builder, value, _) => builder..add(value),
            BytesBuilder(),
          ),
        )
        .map((builder) => builder.toBytes())
        .last;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'chunkSize': chunkSize,
      'partUploads': partUploads.map((x) => x.toJson()).toList(),
      'completeUploadUrl': completeUploadUrl,
      'file': file.path,
      'fileSize': fileSize,
    };
  }

  factory AwsUploadManager.fromMap(
    Map<String, dynamic> map, {
    void Function()? onDone,
  }) {
    return AwsUploadManager(
      chunkSize: map['chunkSize'] as int,
      partUploads: (map['partUploads'] as List<dynamic>)
          .map<String>((e) => e as String)
          .map(PartUpload.fromJson)
          .toList(),
      completeUploadUrl: map['completeUploadUrl'] as String,
      file: XFile(map['file'] as String),
      fileSize: map['fileSize'] as int,
      onDone: onDone,
    );
  }

  String toJson() => json.encode(toMap());

  factory AwsUploadManager.fromJson(String source) =>
      AwsUploadManager.fromMap(json.decode(source) as Map<String, dynamic>);
}
