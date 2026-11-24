public without sharing class PaymentTermsClientPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> opportunityIds;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public PaymentTermsClientPushJob(Set<Id> opportunityIds) {
        this.opportunityIds = opportunityIds == null
            ? new Set<Id>()
            : new Set<Id>(opportunityIds);
    }

    public void execute(QueueableContext context) {

        if (opportunityIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PAYMENT TERMS PUSH: No Opportunity IDs.'
            );
            return;
        }

        // =====================================================
        // 1. GET ELIGIBLE OPPORTUNITIES
        // =====================================================

        List<Opportunity> opportunities = [
            SELECT
                Id,
                Name,
                Payment_Terms_Status__c,
                Payment_Term_Manager_Remarks__c,
                Payment_Term_Client_Remarks__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND Payment_Terms_Status__c =
                  'Sent for Client Approval'
              AND Payment_Terms_Approved_Date__c != null
            ORDER BY Id
        ];

        if (opportunities.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PAYMENT TERMS PUSH: No eligible Opportunities.'
            );
            return;
        }

        Set<Id> eligibleOpportunityIds = new Set<Id>();

        for (Opportunity opp : opportunities) {
            eligibleOpportunityIds.add(opp.Id);
        }

        // =====================================================
        // 2. GET CONVERTED LEADS FOR THE ACTUAL PROJECTS
        // =====================================================

        Map<Id, Lead> leadByOpportunity =
            new Map<Id, Lead>();

        Map<Id, Id> accountByEventLead =
            new Map<Id, Id>();

        Set<Id> originalAccountLeadIds =
            new Set<Id>();

        for (Lead prospect : [
            SELECT
                Id,
                IsConverted,
                ConvertedOpportunityId,
                ConvertedContactId,
                Portal_Account_Key__c,
                CreatedDate
            FROM Lead
            WHERE IsConverted = true
              AND ConvertedOpportunityId
                  IN :eligibleOpportunityIds
            ORDER BY CreatedDate ASC, Id ASC
        ]) {

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
                'PAYMENT TERMS PUSH: No converted Leads found.'
            );
            return;
        }

        // =====================================================
        // 3. FIND ALL PROJECT LEADS FOR EACH CUSTOMER ACCOUNT
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

        Map<Id, Set<Id>> contactIdsByAccount =
            new Map<Id, Set<Id>>();

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        Set<Id> allProjectLeadIds = new Set<Id>();

        for (Id accountId : originalAccountLeadIds) {

            projectCountByAccount.put(accountId, 0);

            contactIdsByAccount.put(
                accountId,
                new Set<Id>()
            );

            tokensByAccount.put(
                accountId,
                new Set<String>()
            );
        }

        // =====================================================
        // 4. NUMBER THE PROJECTS
        // =====================================================

        for (Lead projectLead : projectLeads) {

            Id accountId =
                resolveOriginalLeadId(projectLead);

            if (!originalAccountLeadIds.contains(accountId)) {
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
        // 5. GET PROSPECT DEVICE TOKENS ACCOUNT-WIDE
        // =====================================================

        Integer prospectTokenCount = 0;

        for (Prospect_Device_Token__c device : [
            SELECT
                Id,
                Prospect_Lead__c,
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

            tokensByAccount.get(accountId).add(
                device.FCM_Token__c.trim()
            );
        }

        // =====================================================
        // 6. GET CONTACT DEVICE TOKENS ACCOUNT-WIDE
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

                accountsByContact.get(contactId).add(accountId);
            }
        }

        Integer mobileTokenCount = 0;

        if (!allContactIds.isEmpty()) {

            for (Mobile_Device_Token__c device : [
                SELECT
                    Id,
                    Contact__c,
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

                Set<Id> linkedAccounts =
                    accountsByContact.get(device.Contact__c);

                if (linkedAccounts == null) {
                    continue;
                }

                for (Id accountId : linkedAccounts) {
                    tokensByAccount.get(accountId).add(
                        device.FCM_Token__c.trim()
                    );
                }
            }
        }

        // =====================================================
        // 7. SEND PAYMENT TERMS NOTIFICATIONS
        // =====================================================

        Integer attempts = 0;
        Integer completed = 0;
        Integer failed = 0;

        Boolean limitReached = false;

        for (Opportunity opp : opportunities) {

            Lead prospect =
                leadByOpportunity.get(opp.Id);

            if (prospect == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'PAYMENT TERMS PUSH: No Lead for ' + opp.Id
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

            Set<String> candidateTokens =
                tokensByAccount.get(accountLeadId);

            if (
                candidateTokens == null ||
                candidateTokens.isEmpty()
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'PAYMENT TERMS PUSH: No active device token. ' +
                    'Lead=' + prospect.Id +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            // =================================================
            // 8. PROJECT-SPECIFIC NOTIFICATION TITLE
            // =================================================

            String title =
                'Arelia - ' + projectLabel +
                ': Payment Terms Ready for Review';

            // Preserve your existing notification message.
            String body =
                'Your payment terms are ready for your approval. ' +
                'Tap to review the details.';

            String notificationType =
                'PAYMENT_TERMS_SENT_FOR_CLIENT_APPROVAL';

            Map<String, String> payload =
                new Map<String, String>{

                    'recipientType' =>
                        'prospect',

                    'notificationType' =>
                        notificationType,

                    'type' =>
                        notificationType,

                    'actionType' =>
                        'OPEN_PAYMENT_TERMS',

                    'route' =>
                        'prospect_payment_terms',

                    // Actual project Lead.
                    'leadId' =>
                        String.valueOf(prospect.Id),

                    // Original customer account Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    // Converted Contact of this project.
                    'contactId' =>
                        prospect.ConvertedContactId == null
                            ? ''
                            : String.valueOf(
                                prospect.ConvertedContactId
                            ),

                    // Exact Opportunity for this project.
                    'opportunityId' =>
                        String.valueOf(opp.Id),

                    'recordId' =>
                        String.valueOf(opp.Id),

                    'id' =>
                        notificationType + ':' +
                        String.valueOf(opp.Id),

                    'title' =>
                        title,

                    'body' =>
                        body,

                    'time' =>
                        Datetime.now().formatGMT(
                            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                        ),

                    'source' =>
                        'Lead',

                    'projectLabel' =>
                        projectLabel
                };

            if (projectLabel.startsWith('Project ')) {
                payload.put(
                    'projectNumber',
                    projectLabel.substring(8)
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'PAYMENT TERMS MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', Opportunity=' + opp.Id +
                ', Lead=' + prospect.Id +
                ', Account=' + accountLeadId +
                ', Devices=' + candidateTokens.size()
            );

            // =================================================
            // 9. SEND TO EACH UNIQUE DEVICE
            // =================================================

            // The account Set already removes duplicate FCM
            // tokens, but each project event is sent separately.

            for (String token : candidateTokens) {

                if (String.isBlank(token)) {
                    continue;
                }

                if (
                    attempts >= MAX_PUSH_ATTEMPTS ||
                    Limits.getCallouts() >=
                        Limits.getLimitCallouts() - 2
                ) {
                    limitReached = true;

                    System.debug(
                        LoggingLevel.WARN,
                        'PAYMENT TERMS PUSH: Callout safety limit reached.'
                    );

                    break;
                }

                attempts++;

                try {

                    FirebasePushService.sendPushToToken(
                        token,
                        title,
                        body,
                        payload
                    );

                    completed++;

                    System.debug(
                        LoggingLevel.INFO,
                        'PAYMENT TERMS PUSH REQUEST COMPLETED. ' +
                        'Project=' + projectLabel +
                        ', Opportunity=' + opp.Id +
                        ', Lead=' + prospect.Id
                    );

                } catch (Exception ex) {

                    failed++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'PAYMENT TERMS PUSH FAILED. ' +
                        'Opportunity=' + opp.Id +
                        ', Error=' + ex.getMessage()
                    );
                }
            }

            if (limitReached) {
                break;
            }
        }

        // =====================================================
        // 10. EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '=== PAYMENT TERMS MULTI-PROJECT PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Opportunities=' + opportunities.size() +
            ', ProspectTokens=' + prospectTokenCount +
            ', MobileTokens=' + mobileTokenCount +
            ', Attempts=' + attempts +
            ', Completed=' + completed +
            ', Failed=' + failed +
            ', CalloutLimitReached=' + limitReached
        );
    }

    // =====================================================
    // 11. RESOLVE ORIGINAL CUSTOMER LEAD
    // =====================================================

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
                'PAYMENT TERMS PUSH: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }
}