trigger AreliaPaymentNotificationTrigger on Payment_Term__c (before insert, before update, after update) {
    if (Trigger.isBefore) {
        PaymentAmountSnapshotHandler.validate(
            Trigger.new,
            Trigger.isUpdate ? Trigger.oldMap : null
        );
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        AreliaPaymentNotificationHandler.handleAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );
    }
}