import 'dart:async';

import 'package:aws_upload_file/aws_upload_file.dart';
import 'package:example/upload_progress_indicator.dart';
import 'package:example/urls.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aws Upload Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Aws Upload Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late AwsUploadFile _awsUploadFile;
  ValueStream<double>? _uploadStream;
  StreamSubscription? _progressSub;

  @override
  void initState() {
    super.initState();

    _awsUploadFile = AwsUploadFile();
    _awsUploadFile.config().then((_) => debugPrint("LOGGO - config completed"));
  }

  @override
  void dispose() {
    _cancelSubs();

    super.dispose();
  }

  void _startUpload() async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null) return;

    final xFile = result.files.single.xFile;
    final fileSize = await xFile.length();
    debugPrint("LOGGO - filePath ${xFile.path}");

    final stream = await _awsUploadFile.uploadFile(
      xFile,
      partUploadUrls: partUploadUrls,
      completeUploadUrl: completeUploadUrl,
      fileSize: fileSize,
    );

    setState(() {
      _uploadStream = stream;
    });

    _createSubscription();
  }

  void _resumeVideo() async {
    _cancelSubs();
    setState(() {
      _uploadStream = _awsUploadFile.resumeUploadFile();
    });
    _createSubscription();
  }

  void _cancelVideo() async {
    _awsUploadFile.cancelUpload();
    _cancelSubs();

    setState(() {
      _uploadStream = null;
    });
  }

  void _createSubscription() {
    _progressSub = _uploadStream!.listen((_) {}, onDone: () {
      debugPrint("LOGGO - upload completed");
    }, onError: (error) {
      debugPrint("LOGGO - error $error");
    });
  }

  void _cancelSubs() {
    _progressSub?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UploadProgressIndicator(uploadStream: _uploadStream),
            TextButton(
              onPressed: _startUpload,
              child: const Text(
                'Start upload',
              ),
            ),
            TextButton(
              onPressed: _resumeVideo,
              child: const Text(
                'Resume',
              ),
            ),
            TextButton(
              onPressed: _cancelVideo,
              child: const Text(
                'Cancel',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
