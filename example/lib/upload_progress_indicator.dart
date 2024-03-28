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
        if (snapshot.connectionState == ConnectionState.done) {
          return const Text("Upload completed");
        }
        final double progress = snapshot.hasData ? snapshot.data! : 0.0;
        final int percentage = (progress * 100).round();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              Text(
                'Your upload progress: $percentage%',
              ),
              LinearProgressIndicator(value: progress),
              const Padding(
                padding: EdgeInsets.only(bottom: 16.0),
              ),
              CircularProgressIndicator(value: progress),
            ],
          ),
        );
      },
    );
  }
}
