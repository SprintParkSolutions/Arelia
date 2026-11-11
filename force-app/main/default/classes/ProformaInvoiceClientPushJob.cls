public without sharing class ProformaInvoiceClientPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> invoiceIds;
    private String notificationEvent;

    private static final String EVENT_PROFORMA_SENT =
        'PROFORMA_SENT';

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public ProformaInvoiceClientPushJob(
        Set<Id> invoiceIds,
        String notificationEvent
    ) {
        this.invoiceIds = invoiceIds == null
            ? new Set<Id>()
            : new Set<Id>(invoiceIds);

        this.notificationEvent = notificationEvent;
    }

    public void execute(QueueableContext context) {

        if (
            invoiceIds.isEmpty() ||
            notificationEvent != EVENT_PROFORMA_SENT
        ) {
            System.debug(
                LoggingLevel.WARN,
                'PROFORMA PUSH: Empty invoice IDs or invalid event.'
            );
            return;
        }

        // =====================================================
        // 1. GET PROFORMA INVOICES
        // =====================================================

        List<Proforma_Invoice__c> invoices = [
            SELECT
                Id,
                Name,
                Opportunity__c,
                Project__c,
                Secure_Token__c,
                Status__c
            FROM Proforma_Invoice__c
            WHERE Id IN :invoiceIds
        ];

        Set<Id> opportunityIds = new Set<Id>();

        for (Proforma_Invoice__c inv : invoices) {
            if (inv.Opportunity__c != null) {
                opportunityIds.add(inv.Opportunity__c);
            }
        }

        if (opportunityIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PROFORMA PUSH: No Opportunity IDs found.'
            );
            return;
        }

        // =====================================================
        // 2. FIND CONVERTED LEADS
        // =====================================================

        Map<Id, Lead> leadByOpportunity =
            new Map<Id, Lead>();

        Map<Id, Id> accountByEventLead =
            new Map<Id, Id>();

        Set<Id> originalAccountLeadIds =
            new Set<Id>();

        List<Lead> convertedLeads = [
            SELECT
                Id,
                ConvertedOpportunityId,
                ConvertedContactId,
                IsConverted,
                Portal_Account_Key__c,
                CreatedDate
            FROM Lead
            WHERE ConvertedOpportunityId IN :opportunityIds
              AND IsConverted = true
            ORDER BY CreatedDate ASC, Id ASC
        ];

        for (Lead prospect : convertedLeads) {

            if (
                prospect.ConvertedOpportunityId == null ||
                leadByOpportunity.containsKey(
                    prospect.ConvertedOpportunityId
                )
            ) {
                continue;
            }

            leadByOpportunity.put(
                prospect.ConvertedOpportunityId,
                prospect
            );

            Id accountLeadId =
                resolveOriginalLeadId(prospect);

            accountByEventLead.put(
                prospect.Id,
                accountLeadId
            );

            originalAccountLeadIds.add(accountLeadId);
        }

        if (leadByOpportunity.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PROFORMA PUSH: No converted Leads found.'
            );
            return;
        }

        // =====================================================
        // 3. FETCH ALL PROJECT LEADS IN CUSTOMER ACCOUNT
        // =====================================================

        Set<String> accountKeys = new Set<String>();

        for (Id accountId : originalAccountLeadIds) {
            accountKeys.add(String.valueOf(accountId));
        }

        List<Lead> projectLeads = [
            SELECT
                Id,
                CreatedDate,
                Portal_Account_Key__c,
                IsConverted,
                ConvertedContactId
            FROM Lead
            WHERE Id IN :originalAccountLeadIds
               OR Portal_Account_Key__c IN :accountKeys
            ORDER BY CreatedDate ASC, Id ASC
        ];

        Map<Id, Id> accountByProjectLead =
            new Map<Id, Id>();

        Map<Id, String> projectLabelByLead =
            new Map<Id, String>();

        Map<Id, Integer> projectCountByAccount =
            new Map<Id, Integer>();

        Set<Id> allProjectLeadIds = new Set<Id>();

        Map<Id, Set<Id>> contactIdsByAccount =
            new Map<Id, Set<Id>>();

        for (Id accountId : originalAccountLeadIds) {

            projectCountByAccount.put(accountId, 0);

            contactIdsByAccount.put(
                accountId,
                new Set<Id>()
            );
        }

        // =====================================================
        // 4. ASSIGN PROJECT NUMBERS
        // =====================================================

        for (Lead projectLead : projectLeads) {

            Id accountId =
                resolveOriginalLeadId(projectLead);

            if (
                !originalAccountLeadIds.contains(accountId)
            ) {
                continue;
            }

            accountByProjectLead.put(
                projectLead.Id,
                accountId
            );

            allProjectLeadIds.add(projectLead.Id);

            Integer projectNumber =
                projectCountByAccount.get(accountId) + 1;

            projectCountByAccount.put(
                accountId,
                projectNumber
            );

            projectLabelByLead.put(
                projectLead.Id,
                'Project ' + String.valueOf(projectNumber)
            );

            if (projectLead.ConvertedContactId != null) {
                contactIdsByAccount.get(accountId).add(
                    projectLead.ConvertedContactId
                );
            }
        }

        // =====================================================
        // 5. GET ACTIVE PROSPECT TOKENS ACCOUNT-WIDE
        // =====================================================

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        for (Id accountId : originalAccountLeadIds) {
            tokensByAccount.put(
                accountId,
                new Set<String>()
            );
        }

        // Track token records for invalid-token cleanup.
        Map<String, List<Id>> prospectIdsByToken =
            new Map<String, List<Id>>();

        Integer prospectTokenCount = 0;

        for (Prospect_Device_Token__c device : [
            SELECT
                Id,
                Prospect_Lead__c,
                Device_Id__c,
                FCM_Token__c,
                Active__c,
                Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :allProjectLeadIds
              AND Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST
        ]) {

            prospectTokenCount++;

            if (
                device.Prospect_Lead__c == null ||
                String.isBlank(device.FCM_Token__c)
            ) {
                continue;
            }

            Id accountId =
                accountByProjectLead.get(
                    device.Prospect_Lead__c
                );

            if (
                accountId == null ||
                !tokensByAccount.containsKey(accountId)
            ) {
                continue;
            }

            String fcmToken = device.FCM_Token__c.trim();

            tokensByAccount.get(accountId).add(fcmToken);

            if (!prospectIdsByToken.containsKey(fcmToken)) {
                prospectIdsByToken.put(
                    fcmToken,
                    new List<Id>()
                );
            }

            prospectIdsByToken.get(fcmToken).add(device.Id);
        }

        // =====================================================
        // 6. GET CONVERTED CONTACT TOKENS ACCOUNT-WIDE
        // =====================================================

        Set<Id> allContactIds = new Set<Id>();

        Map<Id, Set<Id>> accountsByContact =
            new Map<Id, Set<Id>>();

        for (Id accountId : contactIdsByAccount.keySet()) {

            for (
                Id contactId :
                contactIdsByAccount.get(accountId)
            ) {
                allContactIds.add(contactId);

                if (!accountsByContact.containsKey(contactId)) {
                    accountsByContact.put(
                        contactId,
                        new Set<Id>()
                    );
                }

                accountsByContact.get(contactId).add(
                    accountId
                );
            }
        }

        Map<String, List<Id>> mobileIdsByToken =
            new Map<String, List<Id>>();

        Integer mobileTokenCount = 0;

        if (!allContactIds.isEmpty()) {

            for (Mobile_Device_Token__c device : [
                SELECT
                    Id,
                    Contact__c,
                    Device_Id__c,
                    FCM_Token__c,
                    Active__c,
                    Last_Seen__c
                FROM Mobile_Device_Token__c
                WHERE Contact__c IN :allContactIds
                  AND Active__c = true
                ORDER BY Last_Seen__c DESC NULLS LAST
            ]) {

                mobileTokenCount++;

                if (
                    device.Contact__c == null ||
                    String.isBlank(device.FCM_Token__c)
                ) {
                    continue;
                }

                String fcmToken =
                    device.FCM_Token__c.trim();

                Set<Id> linkedAccounts =
                    accountsByContact.get(device.Contact__c);

                if (linkedAccounts == null) {
                    continue;
                }

                for (Id accountId : linkedAccounts) {
                    tokensByAccount.get(accountId).add(
                        fcmToken
                    );
                }

                if (!mobileIdsByToken.containsKey(fcmToken)) {
                    mobileIdsByToken.put(
                        fcmToken,
                        new List<Id>()
                    );
                }

                mobileIdsByToken.get(fcmToken).add(device.Id);
            }
        }

        // =====================================================
        // 7. SEND PROFORMA NOTIFICATIONS PER INVOICE
        // =====================================================

        Map<Id, Prospect_Device_Token__c>
            staleLeadDevices =
                new Map<Id, Prospect_Device_Token__c>();

        Map<Id, Mobile_Device_Token__c>
            staleContactDevices =
                new Map<Id, Mobile_Device_Token__c>();

        Set<String> invalidTokens = new Set<String>();

        Integer totalAttempts = 0;
        Integer successfulCount = 0;
        Integer failedCount = 0;

        Boolean reachedLimit = false;

        for (Proforma_Invoice__c inv : invoices) {

            // Preserve original Sent status requirement.
            if (inv.Status__c != 'Sent') {
                System.debug(
                    LoggingLevel.WARN,
                    'PROFORMA PUSH: Invoice not Sent: ' + inv.Id
                );
                continue;
            }

            // Preserve Opportunity and secure token validation.
            if (
                inv.Opportunity__c == null ||
                String.isBlank(inv.Secure_Token__c)
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROFORMA PUSH: Missing Opportunity or token: ' +
                    inv.Id
                );
                continue;
            }

            Lead prospect =
                leadByOpportunity.get(inv.Opportunity__c);

            if (prospect == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROFORMA PUSH: No converted Lead. Opportunity=' +
                    inv.Opportunity__c
                );
                continue;
            }

            Id accountLeadId =
                accountByEventLead.get(prospect.Id);

            if (accountLeadId == null) {
                continue;
            }

            String projectLabel =
                projectLabelByLead.containsKey(prospect.Id)
                    ? projectLabelByLead.get(prospect.Id)
                    : 'Your project';

            Set<String> deliveryTokens =
                tokensByAccount.get(accountLeadId);

            if (
                deliveryTokens == null ||
                deliveryTokens.isEmpty()
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROFORMA PUSH: No account-wide active FCM tokens. ' +
                    'Lead=' + prospect.Id +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            // =================================================
            // 8. CREATE PROJECT-SPECIFIC TITLE
            // =================================================

            String title =
                'Arelia - ' + projectLabel +
                ': Proforma Invoice Ready for Review';

            // Preserve existing message.
            String body =
                'Your Proforma Invoice is ready for review. ' +
                'Tap to view and submit your response.';

            String notificationType =
                'PROFORMA_INVOICE_SENT';

            Map<String, String> payload =
                new Map<String, String>{

                    'recipientType' =>
                        'prospect',

                    'notificationType' =>
                        notificationType,

                    'actionType' =>
                        'OPEN_PROFORMA_INVOICE',

                    'route' =>
                        'prospect_proforma_invoice',

                    // Correct project Lead.
                    'leadId' =>
                        String.valueOf(prospect.Id),

                    // Original customer Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    // Correct project Opportunity.
                    'opportunityId' =>
                        String.valueOf(inv.Opportunity__c),

                    // Correct Proforma Invoice.
                    'invoiceId' =>
                        String.valueOf(inv.Id),

                    // Preserve exact secure token for Flutter.
                    'secureToken' =>
                        inv.Secure_Token__c,

                    'recordId' =>
                        String.valueOf(inv.Id),

                    'id' =>
                        notificationType + ':' +
                        String.valueOf(inv.Id),

                    'title' => title,

                    'body' => body,

                    'time' =>
                        Datetime.now().formatGMT(
                            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                        ),

                    'source' => 'Lead',

                    'projectLabel' => projectLabel
                };

            if (projectLabel.startsWith('Project ')) {
                payload.put(
                    'projectNumber',
                    projectLabel.substring(8)
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'PROFORMA MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', Invoice=' + inv.Id +
                ', Lead=' + prospect.Id +
                ', Account=' + accountLeadId +
                ', Opportunity=' + inv.Opportunity__c +
                ', Devices=' + deliveryTokens.size()
            );

            // One notification per unique device per invoice.
            for (String fcmToken : deliveryTokens) {

                if (
                    String.isBlank(fcmToken) ||
                    invalidTokens.contains(fcmToken)
                ) {
                    continue;
                }

                if (
                    totalAttempts >= MAX_PUSH_ATTEMPTS ||
                    Limits.getCallouts() >=
                        Limits.getLimitCallouts() - 2
                ) {
                    reachedLimit = true;

                    System.debug(
                        LoggingLevel.WARN,
                        'PROFORMA PUSH: Callout safety limit reached.'
                    );
                    break;
                }

                totalAttempts++;

                try {

                    FirebasePushService.sendPushToToken(
                        fcmToken,
                        title,
                        body,
                        payload
                    );

                    successfulCount++;

                    System.debug(
                        LoggingLevel.INFO,
                        'PROFORMA PUSH SENT. ' +
                        'Project=' + projectLabel +
                        ', Lead=' + prospect.Id +
                        ', Invoice=' + inv.Id
                    );

                } catch (Exception ex) {

                    failedCount++;

                    String errorMessage =
                        ex.getMessage() == null
                            ? ''
                            : ex.getMessage();

                    System.debug(
                        LoggingLevel.ERROR,
                        'PROFORMA PUSH FAILED. ' +
                        'Invoice=' + inv.Id +
                        ', Error=' + errorMessage
                    );

                    if (isInvalidFirebaseToken(errorMessage)) {

                        invalidTokens.add(fcmToken);

                        // Deactivate matching Prospect token records.
                        if (
                            prospectIdsByToken.containsKey(fcmToken)
                        ) {
                            for (
                                Id tokenId :
                                prospectIdsByToken.get(fcmToken)
                            ) {
                                staleLeadDevices.put(
                                    tokenId,
                                    new Prospect_Device_Token__c(
                                        Id = tokenId,
                                        Active__c = false
                                    )
                                );
                            }
                        }

                        // Deactivate matching Contact token records.
                        if (
                            mobileIdsByToken.containsKey(fcmToken)
                        ) {
                            for (
                                Id tokenId :
                                mobileIdsByToken.get(fcmToken)
                            ) {
                                staleContactDevices.put(
                                    tokenId,
                                    new Mobile_Device_Token__c(
                                        Id = tokenId,
                                        Active__c = false
                                    )
                                );
                            }
                        }
                    }
                }
            }

            if (reachedLimit) {
                break;
            }
        }

        // =====================================================
        // 9. DEACTIVATE INVALID TOKENS AFTER CALLOUTS
        // =====================================================

        if (!staleContactDevices.isEmpty()) {

            try {
                update staleContactDevices.values();
            } catch (DmlException ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'PROFORMA PUSH: Unable to deactivate ' +
                    'invalid Contact tokens: ' +
                    ex.getMessage()
                );
            }
        }

        if (!staleLeadDevices.isEmpty()) {

            try {
                update staleLeadDevices.values();
            } catch (DmlException ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'PROFORMA PUSH: Unable to deactivate ' +
                    'invalid Prospect tokens: ' +
                    ex.getMessage()
                );
            }
        }

        // =====================================================
        // 10. EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '=== PROFORMA MULTI-PROJECT PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Invoices=' + invoices.size()
        );

        System.debug(
            LoggingLevel.INFO,
            'Prospect token records=' + prospectTokenCount
        );

        System.debug(
            LoggingLevel.INFO,
            'Mobile token records=' + mobileTokenCount
        );

        System.debug(
            LoggingLevel.INFO,
            'FCM attempts=' + totalAttempts
        );

        System.debug(
            LoggingLevel.INFO,
            'Successful sends=' + successfulCount
        );

        System.debug(
            LoggingLevel.INFO,
            'Failed sends=' + failedCount
        );

        System.debug(
            LoggingLevel.INFO,
            'Callout limit reached=' + reachedLimit
        );
    }

    // =========================================================
    // 11. RESOLVE ORIGINAL CUSTOMER LEAD
    // =========================================================

    private static Id resolveOriginalLeadId(
        Lead projectLead
    ) {

        if (
            String.isBlank(
                projectLead.Portal_Account_Key__c
            )
        ) {
            return projectLead.Id;
        }

        try {

            Id accountLeadId =
                (Id) projectLead.Portal_Account_Key__c.trim();

            if (
                accountLeadId.getSObjectType() ==
                    Lead.SObjectType
            ) {
                return accountLeadId;
            }

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.WARN,
                'PROFORMA PUSH: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }

    // =========================================================
    // 12. CHECK INVALID FIREBASE TOKEN ERRORS
    // =========================================================

    private static Boolean isInvalidFirebaseToken(
        String errorMessage
    ) {

        if (String.isBlank(errorMessage)) {
            return false;
        }

        String normalizedError =
            errorMessage.toUpperCase();

        return
            normalizedError.contains('UNREGISTERED') ||
            normalizedError.contains('NOTREGISTERED') ||
            normalizedError.contains(
                'REGISTRATION-TOKEN-NOT-REGISTERED'
            ) ||
            normalizedError.contains(
                'INVALID REGISTRATION TOKEN'
            );
    }
}