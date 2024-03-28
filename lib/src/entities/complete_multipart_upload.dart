class CompleteMultipartUploadBody {
  final Map<int, String> etags;

  CompleteMultipartUploadBody({required this.etags});

  String toXML() {
    final String partsXml = etags.entries
        .map((entry) => _partXml(entry.key, entry.value))
        .fold("", (parts, part) => parts + part);
    return '''
<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
$partsXml
</CompleteMultipartUpload>
'''
        .trim();
  }

  String _partXml(int number, String etag) {
    return '''
<Part>
  <ETag>$etag</ETag>
  <PartNumber>$number</PartNumber>
</Part>'''
        .trim();
  }
}
