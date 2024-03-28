abstract class BaseAwsUploadFileException implements Exception {
  final String message;

  const BaseAwsUploadFileException(this.message);

  @override
  String toString() {
    return "${runtimeType.toString()} - $message";
  }
}

class UploadUninitializedException extends BaseAwsUploadFileException {
  const UploadUninitializedException()
      : super("config() must called before any other activity");
}

class UploadAlreadyInProgressException extends BaseAwsUploadFileException {
  const UploadAlreadyInProgressException()
      : super(
          "Upload already in progress, cancel it before starting new upload",
        );
}

class UploadNotInProgressException extends BaseAwsUploadFileException {
  const UploadNotInProgressException()
      : super("No upload to resume/cancel available");
}

class UploadFileReadException extends BaseAwsUploadFileException {
  const UploadFileReadException(Object e)
      : super("Error occured while reading file: $e");
}

class UploadPartResponseException extends BaseAwsUploadFileException {
  const UploadPartResponseException(Object e)
      : super("Error occured with part upload: $e");
}

class UploadCompleteResponseException extends BaseAwsUploadFileException {
  const UploadCompleteResponseException(Object e)
      : super("Error occured with complete request: $e");
}
