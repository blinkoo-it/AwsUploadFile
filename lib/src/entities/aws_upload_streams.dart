import 'package:rxdart/rxdart.dart';

class AwsUploadStreams {
  final ValueStream<double> progressStream;
  final ValueStream<Exception> errorStream;

  AwsUploadStreams({required this.progressStream, required this.errorStream});
}
