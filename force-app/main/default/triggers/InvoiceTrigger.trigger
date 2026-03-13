trigger InvoiceTrigger on Invoice__c (after insert, after update) {
    if (Trigger.isAfter) {
        InvoiceEmailHandler.sendInvoiceEmailOnce(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
    }
}