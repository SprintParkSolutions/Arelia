trigger ProformaManagerApprovalNotificationTrigger
    on Proforma_Invoice__c (after update) {

    // =====================================================
    // 1. EXISTING MOBILE PUSH NOTIFICATION
    // =====================================================

    Set<Id> approvedInvoiceIds = new Set<Id>();

    // NEW: Manager-approved invoices requiring email fallback.
    Set<Id> invoiceIdsForEmail = new Set<Id>();

    // Preserve the previously tested Site-context distinction.
    Boolean isNonSiteContext = Site.getSiteId() == null;

    for (Proforma_Invoice__c newInvoice : Trigger.new) {

        Proforma_Invoice__c oldInvoice =
            Trigger.oldMap.get(newInvoice.Id);

        if (oldInvoice == null) {
            continue;
        }

        // =================================================
        // EXISTING CONDITIONS - UNCHANGED
        // =================================================

        Boolean managerApprovalJustGiven =
            newInvoice.Manager_Approval__c == true &&
            oldInvoice.Manager_Approval__c != true;

        Boolean approvedDateJustPopulated =
            newInvoice.Proforma_Invoice_Approved_Date__c != null &&
            oldInvoice.Proforma_Invoice_Approved_Date__c == null;

        Boolean approvalReady =
            newInvoice.Manager_Approval__c == true &&
            newInvoice.Proforma_Invoice_Approved_Date__c != null &&
            newInvoice.Opportunity__c != null;

        // Existing mobile push logic - unchanged.
        if (
            approvalReady &&
            (
                managerApprovalJustGiven ||
                approvedDateJustPopulated
            )
        ) {
            approvedInvoiceIds.add(newInvoice.Id);
        }

        // =================================================
        // 2. NEW: MANAGER APPROVAL EMAIL FALLBACK
        // =================================================

        // ProformaInvoiceTriggerHandler already sends
        // manager decision notifications when comments
        // are populated.
        //
        // This fallback handles approval from non-Site
        // contexts when manager comments are blank.
        //
        // This avoids a second notification call when
        // the existing handler already processes it.

        Boolean emailFallbackRequired =
            managerApprovalJustGiven &&
            newInvoice.Opportunity__c != null &&
            isNonSiteContext &&
            String.isBlank(newInvoice.Manager_Comments__c);

        if (emailFallbackRequired) {
            invoiceIdsForEmail.add(newInvoice.Id);
        }
    }

    // =====================================================
    // 3. EXISTING MOBILE PUSH JOB - UNCHANGED
    // =====================================================

    if (!approvedInvoiceIds.isEmpty()) {

        System.debug(
            LoggingLevel.INFO,
            'PROFORMA MANAGER APPROVAL: Enqueue push job. IDs=' +
            approvedInvoiceIds
        );

        System.enqueueJob(
            new ProformaManagerApprovalPushJob(
                approvedInvoiceIds
            )
        );
    }

    // =====================================================
    // 4. NEW: CLIENT MANAGER APPROVAL EMAIL
    // =====================================================

    // Reuse existing Proforma manager decision
    // notification functionality.
    //
    // Template and recipient selection remain
    // controlled by ProformaManagerController.

    for (Id invoiceId : invoiceIdsForEmail) {

        try {

            System.debug(
                LoggingLevel.INFO,
                'PROFORMA MANAGER EMAIL: Sending fallback ' +
                'approval notification. Invoice=' + invoiceId
            );

            ProformaManagerController.sendManagerDecisionNotifications(
                    invoiceId,
                    'Approve',
                    null
                );

            System.debug(
                LoggingLevel.INFO,
                'PROFORMA MANAGER EMAIL: Notification ' +
                'method completed. Invoice=' + invoiceId
            );

        } catch (Exception emailException) {

            System.debug(
                LoggingLevel.ERROR,
                'PROFORMA MANAGER EMAIL FAILED. Invoice=' +
                invoiceId +
                ' | Error=' +
                emailException.getMessage() +
                ' | Line=' +
                emailException.getLineNumber()
            );
        }
    }
}