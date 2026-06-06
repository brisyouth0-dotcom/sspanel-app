class PanelApiException implements Exception {
  PanelApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 兼容旧代码引用
typedef SspanelApiException = PanelApiException;

class MfaRequiredException implements Exception {
  MfaRequiredException(this.message);
  final String message;
}
