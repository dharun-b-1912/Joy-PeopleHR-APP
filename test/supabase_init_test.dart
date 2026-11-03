import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workforce_os/core/config/app_env.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Inspect Supabase.initialize and storage persistence', () async {
    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      publishableKey: AppEnv.supabaseAnonKey,
    );

    expect(Supabase.instance.client, isNotNull);
  });
}
