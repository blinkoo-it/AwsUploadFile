import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aws_upload_file/src/entities/complete_multipart_upload.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

import 'package:aws_upload_file/src/entities/part_upload.dart';

class AwsUploadManager {
  final int chunkSize;
  final List<PartUpload> partUploads;
  final String completeUploadUrl;
  final XFile file;
  final int fileSize;
  final void Function()? onDone;

  final BehaviorSubject<int> _progressSubj;
  final BehaviorSubject<int> _chunkCompletedSubj;
  final BehaviorSubject<Exception> _errorSubj;

  final dio = Dio();

  ValueStream<int> get _progressSizeStream => _progressSubj
      .transform(ScanStreamTransformer((sum, value, index) => sum + value, 0))
      .shareValue();

  ValueStream<double> get progressStream =>
      _progressSizeStream.map((sum) => sum / fileSize).shareValue();

  ValueStream<int> get chunkCompletedStream => _chunkCompletedSubj.shareValue();

  ValueStream<Exception> get errorStream => _errorSubj.shareValue();

  AwsUploadManager({
    required this.chunkSize,
    required this.partUploads,
    required this.completeUploadUrl,
    required this.file,
    required this.fileSize,
    this.onDone,
  })  : _progressSubj = BehaviorSubject(),
        _chunkCompletedSubj = BehaviorSubject(),
        _errorSubj = BehaviorSubject() {
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
        _chunkCompletedSubj = BehaviorSubject(),
        _errorSubj = BehaviorSubject() {
    _initStreams();
  }

  _initStreams() {
    final int sentSize = partUploads
        .where((part) => part.completed)
        .map((part) => part.size)
        .fold(0, (sum, value) => sum + value);
    _progressSubj.add(sentSize);
  }

  // TODO everything in try/catch, handle errors
  void startUpload() async {
    final partsToUpload = partUploads.where((part) => !part.completed);
    // TODO at the moment, we upload one part per time
    for (PartUpload partUpload in partsToUpload) {
      await _uploadChunk(partUpload);
    }
    // chunk upload completed, call complete upload url
    await _completeUpload();
  }

  // TODO everything in try/catch, handle errors
  void resumeUpload() {
    if (progressStream.hasValue) {
      // restore upload progress stream
      final int actualProgress = partUploads
          .where((part) => part.completed)
          .fold(0, (sum, part) => sum + part.size);
      final int diff = actualProgress - _progressSizeStream.value;
      _progressSubj.add(diff);
    }
    startUpload();
  }

  void cancelUpload() {
    // TODO implement
  }

  Future<void> _uploadChunk(PartUpload partUpload) async {
    final int index = partUpload.number - 1;
    final int start = index * chunkSize;
    final int end = start + partUpload.size;

    final Uint8List chunkData = await _readChunkFile(start, end);
    // make call
    final response = await dio.put(
      partUpload.url,
      data: chunkData,
      onSendProgress: (int sent, int tot) => _progressSubj.add(sent),
    );

    if (response.statusCode != 200) {
      // TODO handle error
    }

    final String etag = response.headers["etag"]!.first;
    partUpload.etag = etag;
    partUpload.completed = true;
    _chunkCompletedSubj.add(partUpload.number);
  }

  Future<void> _completeUpload() async {
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
      // TODO handle error
    }
    // close streams
    _chunkCompletedSubj.close();
    _progressSubj.close();
    _errorSubj.close();
  }

  Future<Uint8List> _readChunkFile(int start, int end) async {
    return file
        .openRead(start, end)
        .transform(
          ScanStreamTransformer(
            (sum, value, index) => sum..addAll(value),
            Uint8List(0),
          ),
        )
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
