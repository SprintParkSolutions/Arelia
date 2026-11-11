trigger ProformaInvoiceClientNotificationTrigger
    on Proforma_Invoice__c (after update) {

    Set<Id> sentInvoiceIds = new Set<Id>();

    for (Proforma_Invoice__c newInvoice : Trigger.new) {

        Proforma_Invoice__c oldInvoice =
            Trigger.oldMap.get(newInvoice.Id);

        Boolean wasNone =
            String.isBlank(oldInvoice.Status__c) ||
            oldInvoice.Status__c == 'None';

        Boolean isNowSent =
            newInvoice.Status__c == 'Sent';

        if (wasNone && isNowSent) {

            sentInvoiceIds.add(newInvoice.Id);

            System.debug(
                LoggingLevel.INFO,
                'PROFORMA_SENT: None to Sent detected. Invoice='
                + newInvoice.Id
            );
        }
    }

    if (!sentInvoiceIds.isEmpty()) {

        System.enqueueJob(
            new ProformaInvoiceClientPushJob(
                sentInvoiceIds,
                'PROFORMA_SENT'
            )
        );
    }
}