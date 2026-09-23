trigger AreliaPaymentNotificationTrigger on Payment_Term__c (
    after update
) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        AreliaPaymentNotificationHandler.handleAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );
    }
}