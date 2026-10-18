/// One attempt to deliver a reminder from the cloud (spec 4.6), as recorded by the server.
class NotificationDelivery {
  final String id;
  final String reminderId;
  final String? reminderTitle;
  final String channel;
  final String status;
  final DateTime? fireAt;
  final DateTime? createdAt;
  final String? error;

  const NotificationDelivery({
    required this.id,
    required this.reminderId,
    this.reminderTitle,
    this.channel = 'push',
    required this.status,
    this.fireAt,
    this.createdAt,
    this.error,
  });

  factory NotificationDelivery.fromJson(Map<String, dynamic> json) => NotificationDelivery(
        id: json['id'] as String,
        reminderId: json['reminder_id'] as String? ?? '',
        reminderTitle: json['reminder_title'] as String?,
        channel: json['channel'] as String? ?? 'push',
        status: json['status'] as String? ?? 'triggered',
        fireAt: _date(json['fire_at']),
        createdAt: _date(json['created_at']),
        error: json['error'] as String?,
      );

  static DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  bool get heldByQuietHours => status == 'cancelled' && error == 'quiet hours';

  String get statusLabel {
    if (heldByQuietHours) return 'Held for quiet hours';
    return switch (status) {
      'scheduled' => 'Scheduled',
      'triggered' => 'Started',
      'sent' => 'Sent',
      'delivered' => 'Delivered',
      'failed' => 'Failed',
      'retrying' => 'Retrying',
      'cancelled' => 'Skipped',
      'skipped' => 'Not sent',
      _ => status,
    };
  }

  /// What the status does and does not prove. "Sent" is the provider accepting the message,
  /// not proof it was shown or read, and the screen says so.
  String? get explanation {
    if (heldByQuietHours) return 'Not sent, because it fell inside your quiet hours.';
    return switch (status) {
      'sent' => 'Accepted by the notification service. This does not prove it was shown.',
      'failed' => 'The notification could not be sent.',
      'cancelled' => 'Not sent, because the reminder was no longer needed.',
      'skipped' => error == 'no device registered'
          ? 'No phone was registered for push. Your phone\'s own alarm still rings.'
          : 'Push notifications are not set up yet. Your phone\'s own alarm still rings.',
      _ => null,
    };
  }
}
