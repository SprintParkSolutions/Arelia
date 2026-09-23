trigger ATaskStatusNotificationTrigger on Task (after update) {
    ATaskStatusNotificationHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}