# JOY PeopleHR — Release Notes v1.1.6 (Build 24)

## Google Play Store (Copy-Paste Ready)

```text
• NEW: Learning Management System — browse, enroll & complete training courses on your phone.
• NEW: Video Player with resume playback and quiz assessments.
• NEW: Live Employee Location Map with real-time GPS tracking.
• NEW: Background Shift GPS Tracking (no manual check-in needed).
• Improved push notifications with supervisor privacy controls.
• General stability and performance improvements.
```

---

## Technical Summary

| Area | Change |
|---|---|
| **LMS** | Catalog, YouTube video player (resume + anti-skip), quiz engine with pass score enforcement |
| **Live Location** | Google Maps screen with real-time Supabase-backed employee pins |
| **Shift Tracking** | `ShiftTrackingService` — background foreground service, battery-aware GPS |
| **Notifications** | Supervisor identity stripped from broadcast payloads; deep-link routing for LMS & location |
| **Android** | `ACCESS_BACKGROUND_LOCATION` permission, foreground service declaration in manifest |
| **Data Models** | New `LmsCourseModel`, `ShiftRecord`, `EmployeeLocation` |
| **DB Migration** | `employee_live_locations` table with RLS policies |

## Build Info

| | |
|---|---|
| **AAB** | `JOY_PeopleHR_v1.1.6_build24.aab` (63.9 MB) |
| **Flutter** | 3.47.1 · Dart 3.13.1 |
| **SDK** | Target 36 · Min 24 (Android 7.0+) |
| **Signed** | `joy-peoplehr-release.jks` ✅ |
