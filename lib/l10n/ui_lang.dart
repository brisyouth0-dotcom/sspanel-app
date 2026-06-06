enum UiLang {
  simplifiedChinese,
  traditionalChinese,
  english;

  bool get isEn => this == UiLang.english;

  bool get isHant => this == UiLang.traditionalChinese;

  bool get isSimplified => this == UiLang.simplifiedChinese;

  String get menuLabel => switch (this) {
        UiLang.simplifiedChinese => '简体中文',
        UiLang.traditionalChinese => '繁體中文',
        UiLang.english => 'English',
      };

  static UiLang decode(String? code) {
    switch (code) {
      case 'en':
        return UiLang.english;
      case 'zh_Hant':
      case 'zh_TW':
        return UiLang.traditionalChinese;
      case 'zh_Hans':
      case 'zh_CN':
      default:
        return UiLang.simplifiedChinese;
    }
  }

  String encode() => switch (this) {
        UiLang.english => 'en',
        UiLang.traditionalChinese => 'zh_Hant',
        UiLang.simplifiedChinese => 'zh_Hans',
      };
}
