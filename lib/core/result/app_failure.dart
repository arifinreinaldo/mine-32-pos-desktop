/// Expected, recoverable failures passed across layer boundaries via [Result].
///
/// Unexpected/programmer errors should still throw; these model business and
/// infrastructure failures the UI is expected to handle gracefully.
sealed class AppFailure {
  final String message;
  final Object? cause;
  const AppFailure(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message';
}

/// Input failed validation. [fieldErrors] maps field name -> message.
final class ValidationFailure extends AppFailure {
  final Map<String, String> fieldErrors;
  const ValidationFailure(super.message, {this.fieldErrors = const {}, super.cause});
}

/// A requested entity does not exist.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message, {super.cause});
}

/// A business-rule conflict (e.g. unbalanced journal, negative stock disallowed).
final class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message, {super.cause});
}

/// Local persistence failed.
final class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.cause});
}

/// Sync export/import/merge failed.
final class SyncFailure extends AppFailure {
  const SyncFailure(super.message, {super.cause});
}

/// Anything unexpected that was caught and converted to a failure.
final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.message, {super.cause});
}
