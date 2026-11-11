trigger AreliaProjectStatusNotificationTrigger
    on Project__c (after insert, after update) {

    if (Trigger.isInsert) {

        AreliaProjectStatusNotificationHandler.handleAfterInsert(
            Trigger.new
        );

    }

    if (Trigger.isUpdate) {

        AreliaProjectStatusNotificationHandler.handleAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );

    }
}