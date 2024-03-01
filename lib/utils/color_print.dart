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
  if (kReleaseMode) return;
  if (kIsWeb || Platform.isAndroid) {
    switch (color) {
      case 'R':
        _printLines("\x1B[31m", text, "\x1B[0m");
        break;
      case 'G':
        _printLines("\x1B[32m", text, "\x1B[0m");
        break;
      case 'Y':
        _printLines("\x1B[33m", text, "\x1B[0m");
        break;
      case 'B':
        _printLines("\x1B[34m", text, "\x1B[0m");
        break;
      case 'M':
        _printLines("\x1B[35m", text, "\x1B[0m");
        break;
      case 'C':
        _printLines("\x1B[36m", text, "\x1B[0m");
        break;
      case 'W':
        _printLines("\x1B[37m", text, "\x1B[0m");
        break;
      default:
        _printLines("", text, "");
    }
  } else {
    switch (color) {
      case 'R':
        _printLines("🔴 ", text, "");
        break;
      case 'G':
        _printLines("🟢 ", text, "");
        break;
      case 'Y':
        _printLines("🟡 ", text, "");
        break;
      case 'B':
        _printLines("🔵 ", text, "");
        break;
      case 'M':
        _printLines("🟥 ", text, "");
        break;
      case 'C':
        _printLines("🟨 ", text, "");
        break;
      case 'W':
        _printLines("⚪ ", text, "");
        break;
      default:
        _printLines("", text, "");
    }
  }
}

void _printLines(String start, String text, String end) {
  if (kDebugMode || kProfileMode) {
    text.split("\n").forEach((element) {
      // ignore: avoid_print
      print("$start[dev]$element$end");
    });
  }
}
