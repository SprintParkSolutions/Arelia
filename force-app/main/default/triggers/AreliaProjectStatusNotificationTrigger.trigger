trigger AreliaProjectStatusNotificationTrigger on Project__c (after update) {
    AreliaProjectStatusNotificationHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}