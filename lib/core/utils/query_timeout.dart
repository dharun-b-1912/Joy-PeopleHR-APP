import 'dart:async';

/// Default timeout for Supabase queries.
const Duration kDefaultQueryTimeout = Duration(seconds: 15);

/// Wraps a Future with a timeout. Throws [TimeoutException] on timeout,
/// which is caught by the caller's try/catch error handler.
Future<T> withTimeout<T>(Future<T> future, {Duration? timeout}) {
  return future.timeout(timeout ?? kDefaultQueryTimeout);
}
