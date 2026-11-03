import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Responsive Canonical Avatar Variants for High Visual Fidelity & Minimal Bandwidth
enum AvatarVariant {
  small(96),    // 96x96 for Top Navbar, badges, list tiles
  medium(256),  // 256x256 for Standard Profile cards, drawer headers
  large(512),   // 512x512 for Detail screens, Profile page avatar
  master(1024); // 1024x1024 for Master preview & Virtual ID Hero

  final int dimension;
  const AvatarVariant(this.dimension);
}

/// Resolves URL to appropriate variant dimension
String resolveAvatarUrl(String url, {AvatarVariant variant = AvatarVariant.medium}) {
  if (url.isEmpty || url.startsWith('data:image')) return url;

  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  // Supabase Storage versioned path variant replacement: e.g. .../v/2/master.webp -> .../v/2/256.webp
  if (uri.path.contains('/v/')) {
    final segments = List<String>.from(uri.pathSegments);
    if (segments.isNotEmpty) {
      final last = segments.last;
      if (last.contains('.')) {
        final ext = last.split('.').last;
        final targetFileName = variant == AvatarVariant.master ? 'master.$ext' : '${variant.dimension}.$ext';
        segments[segments.length - 1] = targetFileName;
        final newPath = '/${segments.join('/')}';
        return uri.replace(path: newPath).toString();
      }
    }
  }

  // If the URL is already a Supabase Signed URL, preserve query params exactly to avoid breaking HMAC signature
  if (uri.path.contains('/object/sign/') || uri.queryParameters.containsKey('token')) {
    return url;
  }

  // Supabase Image Transformations fallback: specify width and cover resize without forcing square distortion
  final queryParams = Map<String, String>.from(uri.queryParameters);
  queryParams['width'] = (variant.dimension * 2).toString();
  queryParams['resize'] = 'cover';
  queryParams['quality'] = '90';
  return uri.replace(queryParameters: queryParams).toString();
}

/// Universal cross-platform helper to resolve URLs, base64 data URIs, or local files into ImageProvider without throwing _Namespace on Web.
ImageProvider? getAvatarImageProvider(
  String? pathOrUrl, {
  AvatarVariant variant = AvatarVariant.medium,
  int? targetWidth,
  int? targetHeight,
}) {
  if (pathOrUrl == null || pathOrUrl.trim().isEmpty) return null;
  final trimmed = pathOrUrl.trim();

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    final resolvedUrl = resolveAvatarUrl(trimmed, variant: variant);
    final netImage = NetworkImage(resolvedUrl);

    // Apply ResizeImage with width only to maintain authentic portrait/landscape aspect ratio
    if (!kIsWeb && (targetWidth != null || variant != AvatarVariant.master)) {
      final finalWidth = targetWidth ?? (variant.dimension * 2).clamp(96, 1024);
      return ResizeImage(netImage, width: finalWidth);
    }
    return netImage;
  }

  if (trimmed.startsWith('data:image')) {
    try {
      final base64String = trimmed.split(',').last;
      final bytes = base64Decode(base64String);
      final memImage = MemoryImage(bytes);
      if (!kIsWeb && targetWidth != null) {
        return ResizeImage(memImage, width: targetWidth);
      }
      return memImage;
    } catch (_) {
      return null;
    }
  }

  if (!kIsWeb) {
    try {
      final file = File(trimmed);
      if (file.existsSync()) {
        final fileImage = FileImage(file);
        if (targetWidth != null) {
          return ResizeImage(fileImage, width: targetWidth);
        }
        return fileImage;
      }
    } catch (_) {}
  }
  return null;
}

/// Helper widget to display full-bleed profile background in Virtual ID
Widget buildAvatarHeroWidget(String? pathOrUrl, String fallbackInitials) {
  if (pathOrUrl != null && pathOrUrl.trim().isNotEmpty) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final resolvedUrl = resolveAvatarUrl(trimmed, variant: AvatarVariant.master);
      return Image.network(
        resolvedUrl,
        cacheWidth: 1080,
        fit: BoxFit.cover,
        alignment: const Alignment(0.0, -0.20),
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildFallbackHero(fallbackInitials),
      );
    } else if (trimmed.startsWith('data:image')) {
      try {
        final base64String = trimmed.split(',').last;
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          cacheWidth: 1080,
          fit: BoxFit.cover,
          alignment: const Alignment(0.0, -0.20),
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _buildFallbackHero(fallbackInitials),
        );
      } catch (_) {}
    } else if (!kIsWeb) {
      try {
        final file = File(trimmed);
        if (file.existsSync()) {
          return Image.file(
            file,
            cacheWidth: 1080,
            fit: BoxFit.cover,
            alignment: const Alignment(0.0, -0.20),
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildFallbackHero(fallbackInitials),
          );
        }
      } catch (_) {}
    }
  }
  return _buildFallbackHero(fallbackInitials);
}

Widget _buildFallbackHero(String initials) {
  return Container(
    color: const Color(0xFF07563D),
    child: Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Color(0x40FFFFFF),
          fontSize: 90,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

/// Production flicker-free Avatar widget with gapless playback and upper-third centering.
/// Uses genuine employee profile picture; falls back to corporate initials.
class WorkforceAvatar extends StatelessWidget {
  final String? pathOrUrl;
  final String fallbackInitials;
  final String? employeeName;
  final String? gender;
  final String? employeeCode;
  final double size;
  final AvatarVariant variant;
  final Color backgroundColor;
  final TextStyle? textStyle;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  const WorkforceAvatar({
    super.key,
    required this.pathOrUrl,
    required this.fallbackInitials,
    this.employeeName,
    this.gender,
    this.employeeCode,
    this.size = 44,
    this.variant = AvatarVariant.small,
    this.backgroundColor = const Color(0xFF0F5A47),
    this.textStyle,
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = pathOrUrl != null && pathOrUrl!.trim().isNotEmpty;
    final trimmed = hasImage ? pathOrUrl!.trim() : '';
    final int cacheDim = (size * 3).clamp(96, 768).round();

    Widget? imageWidget;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final resolvedUrl = resolveAvatarUrl(trimmed, variant: variant);
      imageWidget = Image.network(
        resolvedUrl,
        width: size,
        height: size,
        cacheWidth: cacheDim,
        fit: BoxFit.cover,
        alignment: const Alignment(0.0, -0.20),
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildInitials(),
      );
    } else if (trimmed.startsWith('data:image')) {
      try {
        final base64String = trimmed.split(',').last;
        final bytes = base64Decode(base64String);
        imageWidget = Image.memory(
          bytes,
          width: size,
          height: size,
          cacheWidth: cacheDim,
          fit: BoxFit.cover,
          alignment: const Alignment(0.0, -0.20),
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _buildInitials(),
        );
      } catch (_) {
        imageWidget = _buildInitials();
      }
    } else if (!kIsWeb && trimmed.isNotEmpty) {
      try {
        final file = File(trimmed);
        if (file.existsSync()) {
          imageWidget = Image.file(
            file,
            width: size,
            height: size,
            cacheWidth: cacheDim,
            fit: BoxFit.cover,
            alignment: const Alignment(0.0, -0.20),
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildInitials(),
          );
        }
      } catch (_) {}
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: border,
        boxShadow: boxShadow,
      ),
      child: ClipOval(
        child: imageWidget ?? _buildInitials(),
      ),
    );
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        fallbackInitials,
        style: textStyle ??
            TextStyle(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
