import 'package:rxdart/rxdart.dart';

extension BehaviourSubjectExtension on BehaviorSubject {
  void addErrorIfNotClosed(Object e) {
    if (!isClosed) {
      addError(e);
    }
  }
}
