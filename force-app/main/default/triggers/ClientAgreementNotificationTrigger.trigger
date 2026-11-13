trigger ClientAgreementNotificationTrigger
    on Opportunity (after update) {

    // Existing Client Agreement Sent notifications.
    Set<Id> opportunityIdsToNotify =
        new Set<Id>();

    // New Client Agreement Signed notifications.
    Set<Id> signedOpportunityIds =
        new Set<Id>();

    for (Opportunity newOpportunity : Trigger.new) {

        Opportunity oldOpportunity =
            Trigger.oldMap.get(newOpportunity.Id);

        if (oldOpportunity == null) {
            continue;
        }

        // =====================================================
        // 1. CLIENT AGREEMENT SENT: FALSE -> TRUE
        // EXISTING FUNCTIONALITY
        // =====================================================

        Boolean agreementJustSent =
            oldOpportunity.Client_Agreement_Sent__c != true
            &&
            newOpportunity.Client_Agreement_Sent__c == true;

        // =====================================================
        // 2. CLIENT AGREEMENT SIGNED: FALSE -> TRUE
        // NEW FUNCTIONALITY
        // =====================================================

        Boolean agreementJustSigned =
            oldOpportunity.Client_Agreement_Signed__c != true
            &&
            newOpportunity.Client_Agreement_Signed__c == true;

        // =====================================================
        // 3. DEBUG LOGS
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '### CLIENT AGREEMENT AUDIT ### ' +
            'Opportunity=' + newOpportunity.Id +
            ', SentOld=' +
                oldOpportunity.Client_Agreement_Sent__c +
            ', SentNew=' +
                newOpportunity.Client_Agreement_Sent__c +
            ', SignedOld=' +
                oldOpportunity.Client_Agreement_Signed__c +
            ', SignedNew=' +
                newOpportunity.Client_Agreement_Signed__c
        );

        // =====================================================
        // 4. EXISTING AGREEMENT SENT NOTIFICATION
        // =====================================================

        if (agreementJustSent) {

            opportunityIdsToNotify.add(
                newOpportunity.Id
            );

            System.debug(
                LoggingLevel.INFO,
                '### CLIENT AGREEMENT SENT DETECTED ### ' +
                newOpportunity.Id
            );
        }

        // =====================================================
        // 5. NEW AGREEMENT SIGNED NOTIFICATION
        // =====================================================

        if (agreementJustSigned) {

            signedOpportunityIds.add(
                newOpportunity.Id
            );

            System.debug(
                LoggingLevel.INFO,
                '### CLIENT AGREEMENT SIGNED DETECTED ### ' +
                newOpportunity.Id
            );
        }
    }

    // =====================================================
    // 6. QUEUE EXISTING AGREEMENT SENT NOTIFICATIONS
    // =====================================================

    if (!opportunityIdsToNotify.isEmpty()) {

        System.enqueueJob(
            new ClientAgreementPushJob(
                opportunityIdsToNotify
            )
        );
    }

    // =====================================================
    // 7. QUEUE NEW AGREEMENT SIGNED NOTIFICATIONS
    // =====================================================

    if (!signedOpportunityIds.isEmpty()) {

        System.enqueueJob(
            new ClientAgreementPushJob(
                signedOpportunityIds,
                true
            )
        );
    }
}