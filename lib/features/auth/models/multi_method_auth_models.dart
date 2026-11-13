enum LoginMethod {
  employeeIdPassword,
  mobilePassword,
  mobileOtp,
  emailPassword;

  String get apiValue {
    switch (this) {
      case LoginMethod.employeeIdPassword:
        return 'employee_id_password';
      case LoginMethod.mobilePassword:
        return 'mobile_password';
      case LoginMethod.mobileOtp:
        return 'mobile_otp';
      case LoginMethod.emailPassword:
        return 'email_password';
    }
  }

  String get title {
    switch (this) {
      case LoginMethod.employeeIdPassword:
        return 'Employee ID + Password';
      case LoginMethod.mobilePassword:
        return 'Mobile Number + Password';
      case LoginMethod.mobileOtp:
        return 'Mobile Number + OTP';
      case LoginMethod.emailPassword:
        return 'Email Address + Password';
    }
  }

  String get subtitle {
    switch (this) {
      case LoginMethod.employeeIdPassword:
        return 'Sign in with your assigned Employee ID';
      case LoginMethod.mobilePassword:
        return 'Login using your registered mobile number';
      case LoginMethod.mobileOtp:
        return 'Receive a one-time SMS verification code';
      case LoginMethod.emailPassword:
        return 'Login using your registered work email';
    }
  }

  static LoginMethod fromApiValue(String? raw) {
    switch (raw) {
      case 'employee_id_password':
        return LoginMethod.employeeIdPassword;
      case 'mobile_password':
        return LoginMethod.mobilePassword;
      case 'mobile_otp':
        return LoginMethod.mobileOtp;
      case 'email_password':
      default:
        return LoginMethod.emailPassword;
    }
  }
}

class PublicLoginConfig {
  final String? organizationId;
  final String? organizationName;
  final String? companyName;
  final List<LoginMethod> enabledMethods;
  final LoginMethod defaultLoginMethod;
  final LoginMethod factoryRecommendedMethod;
  final int otpExpirySeconds;
  final int otpResendCooldownSeconds;
  final int otpMaxAttempts;
  final bool otpProviderConfigured;

  const PublicLoginConfig({
    this.organizationId,
    this.organizationName,
    this.companyName,
    required this.enabledMethods,
    required this.defaultLoginMethod,
    required this.factoryRecommendedMethod,
    this.otpExpirySeconds = 300,
    this.otpResendCooldownSeconds = 30,
    this.otpMaxAttempts = 5,
    this.otpProviderConfigured = true,
  });

  factory PublicLoginConfig.defaults() => const PublicLoginConfig(
        enabledMethods: [
          LoginMethod.employeeIdPassword,
          LoginMethod.mobilePassword,
          LoginMethod.mobileOtp,
          LoginMethod.emailPassword,
        ],
        defaultLoginMethod: LoginMethod.employeeIdPassword,
        factoryRecommendedMethod: LoginMethod.employeeIdPassword,
      );

  factory PublicLoginConfig.fromJson(Map<String, dynamic> json) {
    final rawList = (json['enabledMethods'] as List<dynamic>?) ?? const [];
    final methods = rawList
        .map((e) => LoginMethod.fromApiValue(e?.toString()))
        .toList(growable: false);

    return PublicLoginConfig(
      organizationId: json['organizationId']?.toString(),
      organizationName: json['organizationName']?.toString(),
      companyName: json['companyName']?.toString(),
      enabledMethods:
          methods.isNotEmpty ? methods : PublicLoginConfig.defaults().enabledMethods,
      defaultLoginMethod:
          LoginMethod.fromApiValue(json['defaultLoginMethod']?.toString()),
      factoryRecommendedMethod:
          LoginMethod.fromApiValue(json['factoryRecommendedMethod']?.toString()),
      otpExpirySeconds: (json['otpExpirySeconds'] as num?)?.toInt() ?? 300,
      otpResendCooldownSeconds:
          (json['otpResendCooldownSeconds'] as num?)?.toInt() ?? 30,
      otpMaxAttempts: (json['otpMaxAttempts'] as num?)?.toInt() ?? 5,
      otpProviderConfigured: json['otpProviderConfigured'] as bool? ?? true,
    );
  }
}

class CompanyMembershipOption {
  final String organizationId;
  final String organizationName;
  final String? companyId;
  final String? companyName;
  final String roleCode;
  final String? employeeId;
  final String? employeeCode;
  final bool isDefault;

  const CompanyMembershipOption({
    required this.organizationId,
    required this.organizationName,
    this.companyId,
    this.companyName,
    required this.roleCode,
    this.employeeId,
    this.employeeCode,
    this.isDefault = false,
  });

  factory CompanyMembershipOption.fromJson(Map<String, dynamic> json) {
    return CompanyMembershipOption(
      organizationId: json['organizationId']?.toString() ?? '',
      organizationName:
          json['organizationName']?.toString() ?? 'Company Workspace',
      companyId: json['companyId']?.toString(),
      companyName: json['companyName']?.toString(),
      roleCode: json['roleCode']?.toString() ?? 'employee',
      employeeId: json['employeeId']?.toString(),
      employeeCode: json['employeeCode']?.toString(),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

class MultiMethodGatewayResult {
  final bool ok;
  final String? code;
  final String? message;
  final String? accessToken;
  final String? refreshToken;
  final bool requiresCompanySelection;
  final List<CompanyMembershipOption> companies;
  final String? organizationId;
  final String? organizationName;
  final String? companyName;
  final String? destinationRoute;
  final String? challengeId;
  final String? maskedDestination;
  final int? expiresInSeconds;
  final int? cooldownSeconds;
  final int? remainingAttempts;

  const MultiMethodGatewayResult({
    required this.ok,
    this.code,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.requiresCompanySelection = false,
    this.companies = const [],
    this.organizationId,
    this.organizationName,
    this.companyName,
    this.destinationRoute,
    this.challengeId,
    this.maskedDestination,
    this.expiresInSeconds,
    this.cooldownSeconds,
    this.remainingAttempts,
  });

  factory MultiMethodGatewayResult.fromJson(Map<String, dynamic> json) {
    final session = json['session'] as Map<String, dynamic>?;
    final ctx = json['activeContext'] as Map<String, dynamic>?;
    final rawCompanies = (json['companies'] as List<dynamic>?) ?? const [];

    return MultiMethodGatewayResult(
      ok: json['ok'] as bool? ?? false,
      code: json['code']?.toString(),
      message: json['message']?.toString(),
      accessToken: session?['access_token']?.toString(),
      refreshToken: session?['refresh_token']?.toString(),
      requiresCompanySelection:
          json['requiresCompanySelection'] as bool? ?? false,
      companies: rawCompanies
          .whereType<Map<String, dynamic>>()
          .map(CompanyMembershipOption.fromJson)
          .toList(growable: false),
      organizationId:
          ctx?['organizationId']?.toString() ?? json['organizationId']?.toString(),
      organizationName:
          json['organizationName']?.toString() ?? ctx?['organizationName']?.toString(),
      companyName:
          json['companyName']?.toString() ?? ctx?['companyName']?.toString(),
      destinationRoute: ctx?['destinationRoute']?.toString(),
      challengeId: json['challengeId']?.toString(),
      maskedDestination: json['maskedDestination']?.toString(),
      expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt(),
      cooldownSeconds: (json['cooldownSeconds'] as num?)?.toInt(),
      remainingAttempts: (json['remainingAttempts'] as num?)?.toInt(),
    );
  }
}

