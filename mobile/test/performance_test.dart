import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/interaction_checker.dart';

import 'helpers/real_database.dart';

/// Performance benchmark harness.
///
/// **Note on thresholds.** These tests run against `sqflite_common_ffi` on
/// the desktop, which adds a fixed FFI marshalling cost per query that does
/// not exist on native Android `sqflite`. The dissertation's stricter
/// targets ("< 200 ms search, < 1 s interaction check") are for the
/// production app on a low-end Android phone — those are measured by
/// running the app on a Pixel 4a / Tecno equivalent and reading the
/// timings printed here from `flutter run --profile`.
///
/// What we enforce in this harness is a generous *regression guard*: if
/// any operation gets dramatically slower than the historical baseline
/// captured in [docs/performance_report.md], this fails. The actual
/// dissertation numbers come from on-device measurement.
///
/// Targets (regression-guard, desktop FFI — generous to absorb host
/// machine load variance during CI):
///   * drug search median latency:   < 2000 ms
///   * interaction check (10 meds):  < 5 s
///   * interaction check (2 meds):   < 700 ms
void main() {
  if (realDatabaseSkip != null) {
    test('performance guards', () {}, skip: realDatabaseSkip);
    return;
  }
  final database = createRealDatabaseService();
  final checker = InteractionChecker(database: database);

  tearDownAll(database.close);

  test('drug search latency regression guard (median over 20 queries)',
      timeout: const Timeout(Duration(minutes: 2)),
      () async {
    const queries = [
      'meto',
      'parac',
      'ibu',
      'omep',
      'amox',
      'lisin',
      'simva',
      'metf',
      'asp',
      'warf',
      'tyl',
      'cipro',
      'azith',
      'losart',
      'pred',
      'sert',
      'fluo',
      'pant',
      'rabe',
      'ator',
    ];
    // Warm up the DB connection + LRU cache.
    await database.searchDrugs('warm');

    final timings = <int>[];
    for (final q in queries) {
      final sw = Stopwatch()..start();
      final results = await database.searchDrugs(q, limit: 25);
      sw.stop();
      timings.add(sw.elapsedMilliseconds);
      expect(results, isNotEmpty, reason: 'query "$q" must return rows');
    }

    timings.sort();
    final median = timings[timings.length ~/ 2];
    final p95 = timings[(timings.length * 0.95).floor()];
    // ignore: avoid_print
    print('search: median=${median}ms p95=${p95}ms full=$timings');
    expect(median, lessThan(2000),
        reason: 'desktop FFI ceiling — Android target is 200 ms');
  });

  test('interaction check for a 10-drug regimen regression guard',
      timeout: const Timeout(Duration(minutes: 2)), () async {
    final names = [
      'Warfarin',
      'Ibuprofen',
      'Simvastatin',
      'Metformin',
      'Lisinopril',
      'Amlodipine',
      'Omeprazole',
      'Aspirin',
      'Atorvastatin',
      'Metoprolol',
    ];
    final ids = <int>[];
    for (final name in names) {
      final results = await database.searchDrugs(name, limit: 25);
      final hit = results
          .where((d) => d.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (hit != null) ids.add(hit.id);
    }
    expect(ids.length, greaterThanOrEqualTo(7),
        reason: 'most common drugs should resolve');

    // First run primes the SafetyReport LRU; we measure the SECOND run for
    // the cached path AND the first run for the cold path.
    InteractionChecker.invalidateCache();
    final cold = Stopwatch()..start();
    final coldReport = await checker.run(ids);
    cold.stop();

    final warm = Stopwatch()..start();
    final warmReport = await checker.run(ids);
    warm.stop();

    // ignore: avoid_print
    print(
      'interaction-check 10-drug regimen: cold=${cold.elapsedMilliseconds}ms '
      'warm=${warm.elapsedMilliseconds}ms findings=${coldReport.totalWarnings}',
    );
    expect(coldReport.totalWarnings, warmReport.totalWarnings);
    expect(cold.elapsedMilliseconds, lessThan(5000),
        reason: 'desktop FFI ceiling — Android target is 1 s');
  });

  test('interaction check for a 2-drug pair regression guard', () async {
    final warfarin = await findExactDrug(database, 'Warfarin');
    final ibuprofen = await findExactDrug(database, 'Ibuprofen');

    InteractionChecker.invalidateCache();
    final sw = Stopwatch()..start();
    final report = await checker.run([warfarin.id, ibuprofen.id]);
    sw.stop();
    // ignore: avoid_print
    print('interaction-check 2-drug: ${sw.elapsedMilliseconds}ms');
    expect(report.drugInteractions, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(700),
        reason: 'desktop FFI ceiling — Android target is 250 ms');
  });
}
