class Languages {
  ///
  /// You can set objects as selected in your app, e.g. change UI accordingly to isSelected flag
  ///
  static List<LanguageSelectionModel> languages = [
    LanguageSelectionModel(
        locale: 'en', languageFullName: 'English', isSelected: false),
    LanguageSelectionModel(
        locale: 'pl', languageFullName: 'Polski', isSelected: false),
    LanguageSelectionModel(
        locale: 'af', languageFullName: 'Afrikaans', isSelected: false),
    LanguageSelectionModel(
        locale: 'ar', languageFullName: 'Arabic', isSelected: false),
    LanguageSelectionModel(
        locale: 'az', languageFullName: 'Azerbaijani', isSelected: false),
    LanguageSelectionModel(
        locale: 'bg', languageFullName: 'Bulgarian', isSelected: false),
    LanguageSelectionModel(
        locale: 'bn', languageFullName: 'Bengali', isSelected: false),
    LanguageSelectionModel(
        locale: 'ca', languageFullName: 'Catalan', isSelected: false),
    LanguageSelectionModel(
        locale: 'cs', languageFullName: 'Czech', isSelected: false),
    LanguageSelectionModel(
        locale: 'da', languageFullName: 'Danish', isSelected: false),
    LanguageSelectionModel(
        locale: 'de', languageFullName: 'German', isSelected: false),
    LanguageSelectionModel(
        locale: 'el', languageFullName: 'Greek', isSelected: false),
    LanguageSelectionModel(
        locale: 'es', languageFullName: 'Spanish', isSelected: false),
    LanguageSelectionModel(
        locale: 'et', languageFullName: 'Estonian', isSelected: false),
    LanguageSelectionModel(
        locale: 'fa', languageFullName: 'Persian', isSelected: false),
    LanguageSelectionModel(
        locale: 'fi', languageFullName: 'Finnish', isSelected: false),
    LanguageSelectionModel(
        locale: 'fr', languageFullName: 'French', isSelected: false),
    LanguageSelectionModel(
        locale: 'he', languageFullName: 'Hebrew', isSelected: false),
    LanguageSelectionModel(
        locale: 'hi', languageFullName: 'Hindi', isSelected: false),
    LanguageSelectionModel(
        locale: 'hr', languageFullName: 'Croatian', isSelected: false),
    LanguageSelectionModel(
        locale: 'hu', languageFullName: 'Hungarian', isSelected: false),
    LanguageSelectionModel(
        locale: 'id', languageFullName: 'Indonesian', isSelected: false),
    LanguageSelectionModel(
        locale: 'it', languageFullName: 'Italian', isSelected: false),
    LanguageSelectionModel(
        locale: 'ja', languageFullName: 'Japanese', isSelected: false),
    LanguageSelectionModel(
        locale: 'ka', languageFullName: 'Georgian', isSelected: false),
    LanguageSelectionModel(
        locale: 'kk', languageFullName: 'Kazakh', isSelected: false),
    LanguageSelectionModel(
        locale: 'ko', languageFullName: 'Korean', isSelected: false),
    LanguageSelectionModel(
        locale: 'lt', languageFullName: 'Lithuanian', isSelected: false),
    LanguageSelectionModel(
        locale: 'lv', languageFullName: 'Latvian', isSelected: false),
    LanguageSelectionModel(
        locale: 'mk', languageFullName: 'Macedonian', isSelected: false),
    LanguageSelectionModel(
        locale: 'mn', languageFullName: 'Mongolian', isSelected: false),
    LanguageSelectionModel(
        locale: 'ms', languageFullName: 'Malay', isSelected: false),
    LanguageSelectionModel(
        locale: 'ne', languageFullName: 'Nepali', isSelected: false),
    LanguageSelectionModel(
        locale: 'nl', languageFullName: 'Dutch', isSelected: false),
    LanguageSelectionModel(
        locale: 'no', languageFullName: 'Norwegian', isSelected: false),
    LanguageSelectionModel(
        locale: 'pt', languageFullName: 'Portuguese', isSelected: false),
    LanguageSelectionModel(
        locale: 'ro', languageFullName: 'Romanian', isSelected: false),
    LanguageSelectionModel(
        locale: 'ru', languageFullName: 'Russian', isSelected: false),
    LanguageSelectionModel(
        locale: 'sk', languageFullName: 'Slovak', isSelected: false),
    LanguageSelectionModel(
        locale: 'sl', languageFullName: 'Slovenian', isSelected: false),
    LanguageSelectionModel(
        locale: 'sr', languageFullName: 'Serbian', isSelected: false),
    LanguageSelectionModel(
        locale: 'sv', languageFullName: 'Swedish', isSelected: false),
    LanguageSelectionModel(
        locale: 'sw', languageFullName: 'Swahili', isSelected: false),
    LanguageSelectionModel(
        locale: 'th', languageFullName: 'Thai', isSelected: false),
    LanguageSelectionModel(
        locale: 'tr', languageFullName: 'Turkish', isSelected: false),
    LanguageSelectionModel(
        locale: 'uk', languageFullName: 'Ukrainian', isSelected: false),
    LanguageSelectionModel(
        locale: 'vi', languageFullName: 'Vietnamese', isSelected: false),
    LanguageSelectionModel(
        locale: 'zh', languageFullName: 'Chinese', isSelected: false),
    LanguageSelectionModel(
        locale: 'zu', languageFullName: 'Zulu', isSelected: false),
  ];
}

class LanguageSelectionModel {
  String locale;
  String languageFullName;
  bool isSelected;

  LanguageSelectionModel(
      {required this.locale,
      required this.languageFullName,
      required this.isSelected});
}