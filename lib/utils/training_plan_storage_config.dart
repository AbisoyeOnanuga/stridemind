/// Storage budget for training plans. Keeps device and Firestore usage predictable.
/// See TRAINING_PLAN_HISTORY.md for design.
class TrainingPlanStorageConfig {
  TrainingPlanStorageConfig._();

  /// Max number of non-archived plans kept locally. At cap, oldest is auto-archived on new save.
  static const int maxPlansLocal = 50;

  /// Soft warning when plan count >= this (e.g. 80% of cap). Show dismissible message.
  static int get softWarningThreshold =>
      (maxPlansLocal * 0.8).floor().clamp(1, maxPlansLocal);

  /// Max plans per user when syncing to Firestore (for future cost control).
  static const int maxPlansFirestorePerUser = 20;
}
