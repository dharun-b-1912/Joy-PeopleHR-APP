import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workforce_os/features/auth/controllers/auth_controller.dart';
import 'package:workforce_os/features/auth/models/multi_method_auth_models.dart';
import 'package:workforce_os/features/auth/screens/forgot_password_screen.dart';
import 'package:workforce_os/features/auth/screens/login_screen.dart';
import 'package:workforce_os/features/auth/services/auth_gateway_service.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/repositories/interfaces/auth_repository.dart';

class FakeAuthRepository implements IAuthRepository {
  UserModel? fakeUser;
  bool signedOut = false;

  @override
  Future<AuthResult> authenticateUser({
    required String identifier,
    String? password,
    String? otp,
  }) async {
    return const AuthResult(success: false, errorMessage: 'Unused in gateway tests');
  }

  @override
  Future<UserModel?> restoreSession() async => fakeUser;

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  Future<UserModel?> signInWithPassword(String email, String password) async =>
      fakeUser;

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      true;

  @override
  Future<bool> resetPasswordForEmail(String email) async => true;

  @override
  Future<bool> verifyPassword(String password) async => true;

  @override
  Future<PayrollStatutoryModel?> getSensitiveStatutoryDetails(
          String employeeId) async =>
      null;
}

AuthGatewayService buildGateway(
  Future<http.Response> Function(http.Request request) handler,
) {
  return AuthGatewayService(
    httpClient: MockClient(handler),
    urlProvider: () => 'https://example.supabase.co',
    anonKeyProvider: () => 'sb_publishable_test_key',
  );
}

void main() {
  testWidgets(
    'displays enabled login method selection cards before credential inputs',
    (WidgetTester tester) async {
      final repo = FakeAuthRepository();
      final gateway = buildGateway((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['action'] == 'get_login_config') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'enabledMethods': [
                'employee_id_password',
                'mobile_otp',
                'email_password',
              ],
              'defaultLoginMethod': 'employee_id_password',
              'factoryRecommendedMethod': 'employee_id_password',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'ok': false}), 400);
      });

      final controller = AuthController(
        authRepository: repo,
        gatewayService: gateway,
        sessionHydrator: (_) async {},
      );

      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select your login method'), findsOneWidget);
      expect(find.text('Employee ID + Password'), findsOneWidget);
      expect(
        find.text('Recommended for factory & site workers'),
        findsOneWidget,
      );
      expect(find.text('Mobile Number + OTP'), findsOneWidget);
      expect(find.text('Email Address + Password'), findsOneWidget);
      // Disabled method by HR policy should not render:
      expect(find.text('Mobile Number + Password'), findsNothing);
    },
  );

  testWidgets(
    'selecting Employee ID + Password renders Employee ID fields and signs in cleanly',
    (WidgetTester tester) async {
      final repo = FakeAuthRepository();
      bool loginSuccessCalled = false;
      String? capturedMethod;
      String? capturedIdentifier;

      final gateway = buildGateway((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['action'] == 'get_login_config') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'enabledMethods': [
                'employee_id_password',
                'mobile_password',
                'mobile_otp',
                'email_password',
              ],
              'defaultLoginMethod': 'employee_id_password',
              'factoryRecommendedMethod': 'employee_id_password',
            }),
            200,
          );
        }
        if (body['action'] == 'login_with_password') {
          capturedMethod = body['method']?.toString();
          capturedIdentifier = body['identifier']?.toString();
          return http.Response(
            jsonEncode({
              'ok': true,
              'session': {
                'access_token': 'acc-token',
                'refresh_token': 'ref-token',
              },
              'requiresCompanySelection': false,
              'activeContext': {
                'organizationId': 'org-1',
                'roleCode': 'employee',
                'destinationRoute': '/employee',
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'ok': false}), 400);
      });

      final controller = AuthController(
        authRepository: repo,
        gatewayService: gateway,
        sessionHydrator: (_) async {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            controller: controller,
            onLoginSuccess: () => loginSuccessCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('method_card_employee_id_password')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Change Login Method'), findsOneWidget);
      expect(find.text('Employee ID / Worker Code'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'EMP-101');
      await tester.enterText(find.byType(TextField).at(1), 'Secret@123');
      await tester.ensureVisible(find.text('Sign In'));
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(capturedMethod, 'employee_id_password');
      expect(capturedIdentifier, 'EMP-101');
      expect(loginSuccessCalled, isTrue);
    },
  );

  testWidgets(
    'Mobile Number + OTP requests OTP, displays cooldown countdown, and verifies 6-digit code',
    (WidgetTester tester) async {
      final repo = FakeAuthRepository();
      bool loginSuccessCalled = false;

      final gateway = buildGateway((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['action'] == 'get_login_config') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'enabledMethods': ['employee_id_password', 'mobile_otp'],
              'defaultLoginMethod': 'employee_id_password',
              'factoryRecommendedMethod': 'employee_id_password',
            }),
            200,
          );
        }
        if (body['action'] == 'request_login_otp') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'challengeId': 'chal-otp-1',
              'maskedDestination': '+91******3210',
              'cooldownSeconds': 30,
            }),
            200,
          );
        }
        if (body['action'] == 'verify_login_otp') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'session': {
                'access_token': 'acc-otp',
                'refresh_token': 'ref-otp',
              },
              'requiresCompanySelection': false,
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'ok': false}), 400);
      });

      final controller = AuthController(
        authRepository: repo,
        gatewayService: gateway,
        sessionHydrator: (_) async {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            controller: controller,
            onLoginSuccess: () => loginSuccessCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('method_card_mobile_otp')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send Login OTP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('OTP Verification'), findsOneWidget);
      expect(find.text('+91******3210'), findsOneWidget);
      expect(find.textContaining('Resend OTP in'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('otp_pinput_field')),
          matching: find.byType(EditableText),
        ),
        '654321',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(loginSuccessCalled, isTrue);
      // Dispose controller timer cleanly before test ends
      controller.dispose();
    },
  );

  testWidgets(
    'Multi-company user is presented CompanySelectionScreen before entering app',
    (WidgetTester tester) async {
      final repo = FakeAuthRepository();
      bool hydrated = false;
      String? switchedOrg;
      bool loginSuccessCalled = false;

      final gateway = buildGateway((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['action'] == 'get_login_config') {
          return http.Response(
            jsonEncode(PublicLoginConfig.defaults().toString()),
            400,
          );
        }
        if (body['action'] == 'login_with_password') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'session': {
                'access_token': 'acc-mc',
                'refresh_token': 'ref-mc',
              },
              'requiresCompanySelection': true,
              'companies': [
                {
                  'organizationId': 'org-1',
                  'organizationName': 'Joy Corporate Pvt Ltd',
                  'roleCode': 'employee',
                  'isDefault': true,
                },
                {
                  'organizationId': 'org-2',
                  'organizationName': 'Joy Manufacturing Unit 2',
                  'roleCode': 'hr_head',
                  'isDefault': false,
                },
              ],
            }),
            200,
          );
        }
        if (body['action'] == 'switch_company_context') {
          switchedOrg = body['organizationId']?.toString();
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response(jsonEncode({'ok': false}), 400);
      });

      final controller = AuthController(
        authRepository: repo,
        gatewayService: gateway,
        sessionHydrator: (_) async {
          hydrated = true;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            controller: controller,
            onLoginSuccess: () => loginSuccessCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailCard = find.byKey(const ValueKey('method_card_email_password'));
      await tester.ensureVisible(emailCard);
      await tester.tap(emailCard);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'hr@company.com');
      await tester.enterText(find.byType(TextField).at(1), 'Password123');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(hydrated, isFalse);
      expect(find.text('Select Company Workspace'), findsOneWidget);
      expect(find.text('Joy Manufacturing Unit 2'), findsOneWidget);

      await tester.ensureVisible(find.text('Joy Manufacturing Unit 2'));
      await tester.tap(find.text('Joy Manufacturing Unit 2'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue to Workspace'));
      await tester.tap(find.text('Continue to Workspace'));
      await tester.pumpAndSettle();

      expect(switchedOrg, 'org-2');
      expect(hydrated, isTrue);
      expect(loginSuccessCalled, isTrue);
    },
  );

  testWidgets(
    'ForgotPasswordScreen supports both Email and Mobile OTP reset flows',
    (WidgetTester tester) async {
      final repo = FakeAuthRepository();
      final gateway = buildGateway((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['action'] == 'request_password_recovery') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'challengeId': 'reset-chal-1',
              'maskedDestination': '+91******3210',
              'cooldownSeconds': 30,
            }),
            200,
          );
        }
        if (body['action'] == 'verify_recovery_otp_reset') {
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response(jsonEncode({'ok': false}), 400);
      });

      final controller = AuthController(
        authRepository: repo,
        gatewayService: gateway,
        sessionHydrator: (_) async {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(authController: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mobile OTP'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send Reset OTP'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter the 6-digit OTP sent to +91******3210'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(0), '123456');
      await tester.enterText(find.byType(TextField).at(1), 'NewPass@123');
      await tester.ensureVisible(find.text('Update Password'));
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();

      expect(find.text('Password Updated'), findsOneWidget);
      controller.dispose();
    },
  );
}

