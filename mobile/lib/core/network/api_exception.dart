/// Every API failure is mapped to one of these, so screens can react by type
/// (inline field errors, sign-in prompt, retry view, …) without inspecting HTTP details.
sealed class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.requestId});

  /// Safe to show to the user (comes from the server's `message` or a local fallback).
  final String message;

  /// Stable machine code from the server, e.g. `INVALID_CREDENTIALS`.
  final String? code;

  /// Server request id — shown in error views so problems can be traced in the logs.
  final String? requestId;

  @override
  String toString() => '$runtimeType(${code ?? '-'}): $message';
}

/// No connection, DNS failure, connection refused.
final class NetworkException extends ApiException {
  const NetworkException([super.message = 'No connection to the server. Check your internet and try again.']);
}

/// The server did not answer in time.
final class TimeoutApiException extends ApiException {
  const TimeoutApiException([super.message = 'The server took too long to respond. Please try again.']);
}

/// 401 — missing/invalid credentials or the session has ended.
final class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.message, {super.code, super.requestId});
}

/// 403 — signed in but not allowed (or account disabled).
final class ForbiddenException extends ApiException {
  const ForbiddenException(super.message, {super.code, super.requestId});
}

/// 404
final class NotFoundException extends ApiException {
  const NotFoundException(super.message, {super.code, super.requestId});
}

/// 409 — e.g. version conflict, timer already running.
final class ConflictException extends ApiException {
  const ConflictException(super.message, {super.code, super.requestId});
}

/// 422 — field errors keyed by API field name.
final class ValidationException extends ApiException {
  const ValidationException(super.message, this.fieldErrors, {super.code, super.requestId});

  final Map<String, List<String>> fieldErrors;

  /// First message for a field (for inline form errors), or null.
  String? forField(String field) {
    final messages = fieldErrors[field];
    return messages == null || messages.isEmpty ? null : messages.first;
  }
}

/// 429 — rate limited or account locked.
final class RateLimitedException extends ApiException {
  const RateLimitedException(super.message, {this.retryAfter, super.code, super.requestId});

  final Duration? retryAfter;
}

/// 5xx or an unexpected response.
final class ServerException extends ApiException {
  const ServerException([super.message = 'Something went wrong on our side. Please try again.', String? code, String? requestId])
      : super(code: code, requestId: requestId);
}
