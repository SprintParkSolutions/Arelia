trigger QuotationApprovalTrigger on Quotation__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        QuotationApprovalHandler.handleAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );
    }
}