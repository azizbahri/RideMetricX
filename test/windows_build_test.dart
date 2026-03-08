import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('Windows Build Configuration', () {
    test('Windows CMakeLists.txt exists', () {
      final cmakeFile = File('windows/CMakeLists.txt');
      expect(cmakeFile.existsSync(), isTrue,
          reason: 'windows/CMakeLists.txt must exist for Windows builds');
    });

    test('Windows runner CMakeLists.txt exists', () {
      final runnerCmakeFile = File('windows/runner/CMakeLists.txt');
      expect(runnerCmakeFile.existsSync(), isTrue,
          reason: 'windows/runner/CMakeLists.txt must exist for Windows builds');
    });

    test('Windows flutter CMakeLists.txt exists', () {
      final flutterCmakeFile = File('windows/flutter/CMakeLists.txt');
      expect(flutterCmakeFile.existsSync(), isTrue,
          reason: 'windows/flutter/CMakeLists.txt must exist for Windows builds');
    });

    test('Windows CMakeLists.txt defines apply_standard_settings function', () {
      final cmakeFile = File('windows/CMakeLists.txt');
      final content = cmakeFile.readAsStringSync();
      
      // Verify the apply_standard_settings function is defined
      // This was the missing piece that caused the original CMake error
      expect(content.toLowerCase().contains('function(apply_standard_settings'), isTrue,
          reason: 'apply_standard_settings function must be defined in windows/CMakeLists.txt');
    });

    test('Windows runner CMakeLists.txt uses apply_standard_settings', () {
      final runnerCmakeFile = File('windows/runner/CMakeLists.txt');
      final content = runnerCmakeFile.readAsStringSync();
      
      // Verify the runner uses the apply_standard_settings function
      expect(content.toLowerCase().contains('apply_standard_settings'), isTrue,
          reason: 'Runner CMakeLists.txt should call apply_standard_settings');
    });

    test('Windows main.cpp exists', () {
      final mainFile = File('windows/runner/main.cpp');
      expect(mainFile.existsSync(), isTrue,
          reason: 'windows/runner/main.cpp must exist for Windows builds');
    });

    test('Windows flutter_window.cpp exists', () {
      final flutterWindowFile = File('windows/runner/flutter_window.cpp');
      expect(flutterWindowFile.existsSync(), isTrue,
          reason: 'windows/runner/flutter_window.cpp must exist for Windows builds');
    });
  });
}
