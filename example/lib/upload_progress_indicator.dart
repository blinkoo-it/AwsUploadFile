import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

class UploadProgressIndicator extends StatelessWidget {
  final ValueStream<double>? uploadStream;

  const UploadProgressIndicator({super.key, this.uploadStream});

  @override
  Widget build(BuildContext context) {
    if (uploadStream == null) return const Text("No upload running");
    return StreamBuilder(
      stream: uploadStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return const Text("Upload completed");
        }
        if (snapshot.hasError) {
          return Text("Error: ${snapshot.error}");
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
