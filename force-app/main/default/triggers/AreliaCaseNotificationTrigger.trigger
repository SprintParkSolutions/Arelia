trigger AreliaCaseNotificationTrigger on Case (after update) {
    AreliaCaseNotificationHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}