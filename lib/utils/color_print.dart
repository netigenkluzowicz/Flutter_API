part of '../utils.dart';

/// red (iOS 🔴)
void printR(Object? object) => _print(object.toString(), "R");

/// green (iOS 🟢)
void printG(Object? object) => _print(object.toString(), "G");

/// yellow (iOS 🟡)
void printY(Object? object) => _print(object.toString(), "Y");

/// blue (iOS 🔵)
void printB(Object? object) => _print(object.toString(), "B");

/// magenta (iOS 🟥)
void printM(Object? object) => _print(object.toString(), "M");

/// cyan (iOS 🟨)
void printC(Object? object) => _print(object.toString(), "C");

/// white (iOS ⚪)
void printW(Object? object) => _print(object.toString(), "W");

void _print(String text, String color) {
  if (kIsWeb || Platform.isAndroid) {
    switch (color) {
      case 'R':
        debugPrint("\x1B[31m$text\x1B[0m");
        break;
      case 'G':
        debugPrint("\x1B[32m$text\x1B[0m");
        break;
      case 'Y':
        debugPrint("\x1B[33m$text\x1B[0m");
        break;
      case 'B':
        debugPrint("\x1B[34m$text\x1B[0m");
        break;
      case 'M':
        debugPrint("\x1B[35m$text\x1B[0m");
        break;
      case 'C':
        debugPrint("\x1B[36m$text\x1B[0m");
        break;
      case 'W':
        debugPrint("\x1B[37m$text\x1B[0m");
        break;
      default:
        debugPrint(text);
    }
  } else {
    switch (color) {
      case 'R':
        debugPrint("🔴 $text");
        break;
      case 'G':
        debugPrint("🟢 $text");
        break;
      case 'Y':
        debugPrint("🟡 $text");
        break;
      case 'B':
        debugPrint("🔵 $text");
        break;
      case 'M':
        debugPrint("🟥 $text");
        break;
      case 'C':
        debugPrint("🟨 $text");
        break;
      case 'W':
        debugPrint("⚪ $text");
        break;
      default:
        debugPrint(text);
    }
  }
}
