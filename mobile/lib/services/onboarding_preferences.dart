import 'package:shared_preferences/shared_preferences.dart';

const String kIsFirstLaunchKey = 'is_first_launch';

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kIsFirstLaunchKey, false);
}
