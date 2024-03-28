import 'dart:async';

import 'package:aws_upload_file/aws_upload_file.dart';
import 'package:example/upload_progress_indicator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  AwsUploadStreams? _streams;
  StreamSubscription? _progressSub;
  StreamSubscription? _errorSub;

  @override
  void initState() {
    super.initState();

    _awsUploadFile = AwsUploadFile();
    _awsUploadFile.config().then((_) => print("config completed"));
  }

  void _startUpload() async {
    final List<String> partUploadUrls = [];
    const String completeUploadUrl = "";

    FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null) return;

    final xFile = result.files.single.xFile;
    print(xFile.path);

    setState(() async {
      _streams = await _awsUploadFile.uploadFile(
        xFile,
        partUploadUrls: partUploadUrls,
        completeUploadUrl: completeUploadUrl,
      );
    });

    _createSubs();
  }

  void _resumeVideo() async {
    _cancelSubs();
    setState(() {
      _streams = _awsUploadFile.resumeUploadFile();
    });
    _createSubs();
  }

  void _cancelVideo() async {
    _awsUploadFile.cancelUpload();
    _cancelSubs();

    setState(() {
      _streams = null;
    });
  }

  void _createSubs() {
    _progressSub = _streams!.progressStream.listen(
      (progress) => print("progress $progress"),
      onDone: () {
        print("upload completed");
      },
    );

    _errorSub = _streams!.errorStream.listen(
      (error) => print("error $error"),
    );
  }

  void _cancelSubs() {
    _progressSub?.cancel();
    _errorSub?.cancel();
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
            UploadProgressIndicator(uploadStreams: _streams),
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
