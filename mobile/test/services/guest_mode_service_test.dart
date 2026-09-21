import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/guest_mode_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = GuestModeService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.resetForTest();
  });

  test('defaults to off, so nothing gets past the gate by accident', () async {
    expect(await service.load(), isFalse);
    expect(service.enabled.value, isFalse);
  });

  test('reads a previously stored choice', () async {
    SharedPreferences.setMockInitialValues({
      GuestModeService.storageKey: true,
    });
    service.resetForTest();

    expect(await service.load(), isTrue);
    expect(service.enabled.value, isTrue);
  });

  test('entering persists, so the next launch skips the login wall', () async {
    await service.load();
    await service.enter();

    expect(service.enabled.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(GuestModeService.storageKey), isTrue);
  });

  test('exiting clears the flag when an account takes over', () async {
    SharedPreferences.setMockInitialValues({
      GuestModeService.storageKey: true,
    });
    service.resetForTest();
    await service.load();

    await service.exit();

    expect(service.enabled.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(GuestModeService.storageKey), isFalse);
  });

  test('notifies listeners so gated screens unlock in place', () async {
    await service.load();
    var notifications = 0;
    void listener() => notifications++;
    service.enabled.addListener(listener);
    addTearDown(() => service.enabled.removeListener(listener));

    await service.enter();
    await service.exit();

    expect(notifications, 2);
  });

  test('load is idempotent and does not re-read over a live choice', () async {
    await service.load();
    await service.enter();

    // A second load must not reset the in-memory answer back to the stored
    // one it was called with — startup calls this more than once.
    expect(await service.load(), isTrue);
  });
}
