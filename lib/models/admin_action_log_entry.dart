/// The 8 loggable admin action types — one per actionable (non-read) row
/// in the Roles & Permissions matrix (approve/reject listings, verify
/// licenses, moderate content, suspend/ban, manage payments, assign
/// roles). Purely read-only matrix rows (browse/search, view analytics)
/// aren't "actions" needing an audit trail entry.
enum AdminActionType {
  approveListing,
  rejectListing,
  verifyLicense,
  moderateContent,
  suspendAccount,
  banAccount,
  managePayment,
  assignRole;

  String get wire => switch (this) {
        AdminActionType.approveListing => 'approve_listing',
        AdminActionType.rejectListing => 'reject_listing',
        AdminActionType.verifyLicense => 'verify_license',
        AdminActionType.moderateContent => 'moderate_content',
        AdminActionType.suspendAccount => 'suspend_account',
        AdminActionType.banAccount => 'ban_account',
        AdminActionType.managePayment => 'manage_payment',
        AdminActionType.assignRole => 'assign_role',
      };

  static AdminActionType fromWire(String value) => switch (value) {
        'reject_listing' => AdminActionType.rejectListing,
        'verify_license' => AdminActionType.verifyLicense,
        'moderate_content' => AdminActionType.moderateContent,
        'suspend_account' => AdminActionType.suspendAccount,
        'ban_account' => AdminActionType.banAccount,
        'manage_payment' => AdminActionType.managePayment,
        'assign_role' => AdminActionType.assignRole,
        _ => AdminActionType.approveListing,
      };
}

/// Backs one row of `public.admin_action_log` — the Admin profile schema's
/// "Action Log" field, made real (see that migration's doc comment).
class AdminActionLogEntry {
  final String id;
  final String actorId;
  final AdminActionType actionType;
  final String? targetProfileId;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  const AdminActionLogEntry({
    required this.id,
    required this.actorId,
    required this.actionType,
    this.targetProfileId,
    this.details,
    required this.createdAt,
  });

  factory AdminActionLogEntry.fromJson(Map<String, dynamic> json) => AdminActionLogEntry(
        id: json['id'] as String,
        actorId: json['actor_id'] as String,
        actionType: AdminActionType.fromWire(json['action_type'] as String),
        targetProfileId: json['target_profile_id'] as String?,
        details: json['details'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
