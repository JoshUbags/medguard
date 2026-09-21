import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  test('app source uses Inter for every Google font call', () {
    final offenders = <String>[];

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      if (source.contains('GoogleFonts.dmSans') ||
          source.contains('GoogleFonts.poppins')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });

  test('outlined material icons are limited to inactive bottom navigation', () {
    final offenders = <String>[];
    final sharpIconPattern = RegExp(r'Icons\.[A-Za-z0-9]+_outlined?\b');

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      final isBottomNav = file.path
          .replaceAll('\\', '/')
          .endsWith('lib/widgets/common/floating_nav_bar.dart');
      if (!isBottomNav && sharpIconPattern.hasMatch(source)) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
