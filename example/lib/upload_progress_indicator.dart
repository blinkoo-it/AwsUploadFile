import 'package:aws_upload_file/aws_upload_file.dart';
import 'package:flutter/material.dart';

class UploadProgressIndicator extends StatelessWidget {
  final AwsUploadStreams? uploadStreams;

  const UploadProgressIndicator({super.key, this.uploadStreams});

  @override
  Widget build(BuildContext context) {
    if (uploadStreams == null) return const Text("No upload running");
    return StreamBuilder(
      stream: uploadStreams!.progressStream,
      builder: (context, snapshot) {
        double progress = snapshot.hasData ? snapshot.data! : 0.0;
        return Column(
          children: [
            Text(
              'Your upload progress: ${progress * 100}%',
            ),
            LinearProgressIndicator(value: progress),
          ],
        );
      },
    );
  }
}
