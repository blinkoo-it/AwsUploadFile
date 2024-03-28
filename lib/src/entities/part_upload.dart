import 'dart:convert';

class PartUpload {
  final String url;
  final int number;
  final int size;

  bool completed;
  String? etag;

  PartUpload({
    required this.url,
    required this.number,
    required this.size,
    this.completed = false,
    this.etag,
  });

  PartUpload setCompleted(bool completed) {
    this.completed = completed;
    return this;
  }

  Map<String, dynamic> _toMap() {
    return <String, dynamic>{
      'url': url,
      'number': number,
      'size': size,
      'completed': completed,
      'etag': etag,
    };
  }

  factory PartUpload._fromMap(Map<String, dynamic> map) {
    return PartUpload(
      url: map['url'] as String,
      number: map['number'] as int,
      completed: map['completed'] as bool,
      size: map['size'] as int,
      etag: map['etag'] as String?,
    );
  }

  String toJson() => json.encode(_toMap());

  factory PartUpload.fromJson(String source) =>
      PartUpload._fromMap(json.decode(source) as Map<String, dynamic>);
}
