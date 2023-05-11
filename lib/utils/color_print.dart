import 'dart:io';

import 'package:flutter/material.dart';

void printR(String text) => _print(text, "R");
void printG(String text) => _print(text, "G");
void printY(String text) => _print(text, "Y");
void printB(String text) => _print(text, "B");
void printM(String text) => _print(text, "M");
void printC(String text) => _print(text, "C");
void printW(String text) => _print(text, "W");

void _print(String text, String color) {
  if (Platform.isIOS) {
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
  } else {
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
  }
}
