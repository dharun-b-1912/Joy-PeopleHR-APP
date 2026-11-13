import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce_os/features/face_attend/screens/face_attend_checkin_screen.dart';
import 'package:workforce_os/features/face_attend/services/face_attend_service.dart';
import 'package:workforce_os/features/face_attend/utils/face_embedding_engine.dart';
import 'package:workforce_os/core/services/location_service.dart';

Uint8List _buildSyntheticFaceRgba64({
  required int seed,
  double brightnessOffset = 0,
}) {
  final rgba = Uint8List(64 * 64 * 4);
  for (int y = 0; y < 64; y++) {
    for (int x = 0; x < 64; x++) {
      final dx = (x - 32) / 22.0;
      final dy = (y - 32) / 26.0;
      final distSq = dx * dx + dy * dy;
      int base = distSq <= 1.0 ? 150 : 70;
      // Eyes
      if ((y - 24).abs() < 4 && ((x - 22).abs() < 5 || (x - 42).abs() < 5)) {
        base = 35 + (seed * 7) % 25;
      }
      // Nose bridge
      if ((x - 32).abs() < (2 + seed % 3) && y >= 24 && y <= 40) {
        base = 185 - (seed * 5) % 20;
      }
      // Mouth
      if ((y - (46 + seed % 4)).abs() < 3 && (x - 32).abs() < (8 + seed * 2 % 6)) {
        base = 55;
      }
      final mod = (((x * (seed + 2) + y * (seed * 2 + 1)) % 29) - 14);
      final idx = (y * 64 + x) * 4;
      rgba[idx] = (base + mod + brightnessOffset + 18).round().clamp(10, 245);
      rgba[idx + 1] = (base + mod + brightnessOffset + 4).round().clamp(10, 245);
      rgba[idx + 2] = (base + mod + brightnessOffset - 8).round().clamp(10, 245);
      rgba[idx + 3] = 255;
    }
  }
  return rgba;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JOY FaceAttend Flutter Service & Screen', () {
    test('FaceAttendService starts disabled by default until entitled by backend', () {
      SharedPreferences.setMockInitialValues({});
      final svc = FaceAttendService.instance;
      expect(svc.status.isEntitled, isFalse);
      expect(svc.status.moduleEnabled, isFalse);
    });

    testWidgets('FaceAttendCheckInScreen renders GPS badge and Liveness challenge steps',
        (WidgetTester tester) async {
      final mockLocation = UserLocationResult(
        state: AttendanceGpsState.insideRadius,
        latitude: 11.0168,
        longitude: 76.9558,
        accuracyMeters: 12,
        distanceMeters: 22,
        isInside: true,
        timestamp: DateTime(2026, 11, 12, 9, 0),
        isMock: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FaceAttendCheckInScreen(
            punchType: 'CHECK_IN',
            location: mockLocation,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('FaceAttend Check-In Verification'), findsOneWidget);
      expect(find.textContaining('Location Verified (22m'), findsOneWidget);
      expect(find.textContaining('Natural blink performed'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Capture & Verify Attendance'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.textContaining('Capture & Verify Attendance'), findsOneWidget);
    });

    test('FaceEmbeddingEngine extracts 192-D embedding, matches same face across lighting, and rejects blank frame', () {
      final person1Day1 = _buildSyntheticFaceRgba64(seed: 1, brightnessOffset: 0);
      final person1Day2Morning = _buildSyntheticFaceRgba64(seed: 1, brightnessOffset: 15);
      final person2 = _buildSyntheticFaceRgba64(seed: 9, brightnessOffset: 0);

      final emb1 = FaceEmbeddingEngine.extractFromRgba64(person1Day1);
      final emb1Morning = FaceEmbeddingEngine.extractFromRgba64(person1Day2Morning);
      final emb2 = FaceEmbeddingEngine.extractFromRgba64(person2);

      expect(emb1.hasFace, isTrue);
      expect(emb1.embedding.length, equals(192));
      expect(emb1Morning.hasFace, isTrue);

      final samePersonScore = FaceEmbeddingEngine.compareEmbeddings(
        emb1.embedding,
        emb1Morning.embedding,
      );
      final diffPersonScore = FaceEmbeddingEngine.compareEmbeddings(
        emb1.embedding,
        emb2.embedding,
      );

      expect(samePersonScore, greaterThanOrEqualTo(92.0));
      expect(diffPersonScore, lessThan(samePersonScore));

      // Flat blank wall must be rejected
      final blankRgba = Uint8List.fromList(List<int>.filled(64 * 64 * 4, 128));
      final blankEmb = FaceEmbeddingEngine.extractFromRgba64(blankRgba);
      expect(blankEmb.hasFace, isFalse);
    });
  });
}
