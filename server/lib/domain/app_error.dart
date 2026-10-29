/// An application failure that can be represented by the public error contract.
class AppError implements Exception {
  const AppError(this.code, this.message);

  factory AppError.invalidInput(String message) => AppError('invalidInput', message);
  factory AppError.notFound(String message) => AppError('notFound', message);
  factory AppError.conflict(String message) => AppError('conflict', message);

  final String code;
  final String message;

  @override
  String toString() => 'AppError($code): $message';
}
