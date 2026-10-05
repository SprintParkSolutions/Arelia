trigger ProformaInvoiceMobileTrigger on Proforma_Invoice__c (before insert) {
    // Guarantees Secure_Token__c exists on every Proforma_Invoice__c insert, regardless of
    // source - including clients (e.g. the mobile app) that create the record via the raw
    // REST API and never go through ProformaInvoiceController.sendInvoiceForApproval, which
    // would otherwise leave the approval link token blank.
    ProformaInvoiceTriggerHandler.beforeInsert(Trigger.new);
}