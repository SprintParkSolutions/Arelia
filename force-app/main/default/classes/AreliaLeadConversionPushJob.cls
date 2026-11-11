public without sharing class AreliaLeadConversionPushJob
    implements Queueable, Database.AllowsCallouts {

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    private Set<Id> leadIds;

    public AreliaLeadConversionPushJob(Set<Id> ids) {
        this.leadIds = ids == null
            ? new Set<Id>()
            : new Set<Id>(ids);
    }

    public void execute(QueueableContext context) {

        if (leadIds.isEmpty()) {
            return;
        }

        // =====================================================
        // 1. GET CONVERTED EVENT LEADS
        // =====================================================

        List<Lead> convertedLeads = [
            SELECT
                Id,
                Name,
                IsConverted,
                CreatedDate,
                Portal_Account_Key__c,
                ConvertedOpportunityId,
                ConvertedAccountId,
                ConvertedContactId
            FROM Lead
            WHERE Id IN :leadIds
            WITH SYSTEM_MODE
        ];

        if (convertedLeads.isEmpty()) {
            return;
        }

        // =====================================================
        // 2. RESOLVE ORIGINAL CUSTOMER LEAD
        // =====================================================

        Map<Id, Id> accountLeadByEventLead =
            new Map<Id, Id>();

        Set<Id> originalAccountLeadIds =
            new Set<Id>();

        for (Lead eventLead : convertedLeads) {

            if (
                !eventLead.IsConverted ||
                eventLead.ConvertedOpportunityId == null ||
                eventLead.ConvertedAccountId == null ||
                eventLead.ConvertedContactId == null
            ) {
                continue;
            }

            Id originalLeadId =
                resolveOriginalLeadId(eventLead);

            accountLeadByEventLead.put(
                eventLead.Id,
                originalLeadId
            );

            originalAccountLeadIds.add(
                originalLeadId
            );
        }

        if (originalAccountLeadIds.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'CONVERSION PUSH: No eligible converted Leads.'
            );
            return;
        }

        // =====================================================
        // 3. FETCH ALL PROJECT LEADS FOR THESE ACCOUNTS
        // =====================================================

        Set<String> accountKeys =
            new Set<String>();

        for (Id accountId : originalAccountLeadIds) {
            accountKeys.add(String.valueOf(accountId));
        }

        List<Lead> allProjectLeads = [
            SELECT
                Id,
                Name,
                CreatedDate,
                Portal_Account_Key__c,
                IsConverted,
                ConvertedContactId
            FROM Lead
            WHERE Id IN :originalAccountLeadIds
               OR Portal_Account_Key__c IN :accountKeys
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ];

        // =====================================================
        // 4. BUILD PROJECT ROSTER AND NUMBERING
        // =====================================================

        Map<Id, List<Lead>> projectsByAccount =
            new Map<Id, List<Lead>>();

        Map<Id, Id> accountByProjectLead =
            new Map<Id, Id>();

        Map<Id, String> projectLabels =
            new Map<Id, String>();

        Set<Id> allProjectLeadIds =
            new Set<Id>();

        Set<Id> allConvertedContactIds =
            new Set<Id>();

        for (Id accountId : originalAccountLeadIds) {
            projectsByAccount.put(
                accountId,
                new List<Lead>()
            );
        }

        for (Lead projectLead : allProjectLeads) {

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

            projectsByAccount.get(accountId).add(
                projectLead
            );

            if (
                projectLead.ConvertedContactId != null
            ) {
                allConvertedContactIds.add(
                    projectLead.ConvertedContactId
                );
            }
        }

        // The SOQL query is already ordered by CreatedDate
        // and Id, so numbering is stable for that ordering.
        for (Id accountId : projectsByAccount.keySet()) {

            Integer projectNumber = 0;

            for (
                Lead projectLead :
                projectsByAccount.get(accountId)
            ) {
                projectNumber++;

                projectLabels.put(
                    projectLead.Id,
                    'Project ' +
                    String.valueOf(projectNumber)
                );
            }
        }

        // =====================================================
        // 5. FIND ALL ACTIVE PROSPECT TOKENS
        // =====================================================

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        for (Id accountId : originalAccountLeadIds) {
            tokensByAccount.put(
                accountId,
                new Set<String>()
            );
        }

        List<Prospect_Device_Token__c> prospectTokens = [
            SELECT
                Id,
                Prospect_Lead__c,
                FCM_Token__c,
                Active__c,
                Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :allProjectLeadIds
              AND Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Last_Seen__c DESC
            NULLS LAST
        ];

        for (
            Prospect_Device_Token__c tokenRecord :
            prospectTokens
        ) {

            if (
                tokenRecord.Prospect_Lead__c == null ||
                String.isBlank(tokenRecord.FCM_Token__c)
            ) {
                continue;
            }

            Id accountId =
                accountByProjectLead.get(
                    tokenRecord.Prospect_Lead__c
                );

            if (
                accountId == null ||
                !tokensByAccount.containsKey(accountId)
            ) {
                continue;
            }

            tokensByAccount.get(accountId).add(
                tokenRecord.FCM_Token__c.trim()
            );
        }

        // =====================================================
        // 6. FIND ALL ACTIVE CONVERTED CONTACT TOKENS
        // =====================================================

        Map<Id, Id> accountByContact =
            new Map<Id, Id>();

        for (Lead projectLead : allProjectLeads) {

            if (projectLead.ConvertedContactId == null) {
                continue;
            }

            Id accountId =
                accountByProjectLead.get(projectLead.Id);

            if (accountId != null) {
                accountByContact.put(
                    projectLead.ConvertedContactId,
                    accountId
                );
            }
        }

        if (!allConvertedContactIds.isEmpty()) {

            List<Mobile_Device_Token__c> contactTokens = [
                SELECT
                    Id,
                    Contact__c,
                    FCM_Token__c,
                    Active__c
                FROM Mobile_Device_Token__c
                WHERE Contact__c IN :allConvertedContactIds
                  AND Active__c = true
                WITH SYSTEM_MODE
            ];

            for (
                Mobile_Device_Token__c tokenRecord :
                contactTokens
            ) {

                if (
                    tokenRecord.Contact__c == null ||
                    String.isBlank(tokenRecord.FCM_Token__c)
                ) {
                    continue;
                }

                Id accountId =
                    accountByContact.get(
                        tokenRecord.Contact__c
                    );

                if (
                    accountId == null ||
                    !tokensByAccount.containsKey(accountId)
                ) {
                    continue;
                }

                tokensByAccount.get(accountId).add(
                    tokenRecord.FCM_Token__c.trim()
                );
            }
        }

        // =====================================================
        // 7. SEND CONVERSION NOTIFICATION PER PROJECT
        // =====================================================

        Integer successfulCount = 0;
        Integer failedCount = 0;
        Integer attemptedCount = 0;

        Boolean limitReached = false;

        for (Lead eventLead : convertedLeads) {

            // Preserve the existing eligibility condition.
            if (
                !eventLead.IsConverted ||
                eventLead.ConvertedOpportunityId == null ||
                eventLead.ConvertedAccountId == null ||
                eventLead.ConvertedContactId == null
            ) {
                continue;
            }

            Id accountLeadId =
                accountLeadByEventLead.get(
                    eventLead.Id
                );

            if (accountLeadId == null) {
                continue;
            }

            Set<String> deliveryTokens =
                tokensByAccount.get(accountLeadId);

            String projectLabel =
                projectLabels.containsKey(eventLead.Id)
                    ? projectLabels.get(eventLead.Id)
                    : 'Your project';

            String title =
                'Arelia - ' + projectLabel;

            // Preserve your existing message.
            String body =
                'You will soon receive a 3D design ' +
                'for your review and approval.';

            // =================================================
            // 8. CREATE PROJECT-SPECIFIC FIREBASE PAYLOAD
            // =================================================

            String eventId =
                'LEAD_CONVERTED:' +
                String.valueOf(eventLead.Id);

            String eventTime =
                Datetime.now().formatGMT(
                    'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                );

            Map<String, String> payload =
                new Map<String, String>{

                    'id' => eventId,

                    'title' => title,

                    'body' => body,

                    'time' => eventTime,

                    'source' => 'Lead',

                    'type' => 'lead_converted',

                    'notificationType' =>
                        'LEAD_CONVERTED',

                    'recipientType' =>
                        'prospect',

                    // Actual converted project Lead.
                    'recordId' =>
                        String.valueOf(eventLead.Id),

                    'leadId' =>
                        String.valueOf(eventLead.Id),

                    // Original customer login Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    // Actual converted Opportunity.
                    'opportunityId' =>
                        String.valueOf(
                            eventLead.ConvertedOpportunityId
                        ),

                    'contactId' =>
                        String.valueOf(
                            eventLead.ConvertedContactId
                        ),

                    'projectName' =>
                        projectLabel,

                    'projectLabel' =>
                        projectLabel
                };

            // Include project number if available.
            if (projectLabels.containsKey(eventLead.Id)) {

                String numberText =
                    projectLabel.replace('Project ', '');

                payload.put(
                    'projectNumber',
                    numberText
                );
            }

            Integer tokenCount =
                deliveryTokens == null
                    ? 0
                    : deliveryTokens.size();

            System.debug(
                LoggingLevel.INFO,
                'CONVERSION MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', eventLead=' + eventLead.Id +
                ', accountLead=' + accountLeadId +
                ', opportunity=' +
                    eventLead.ConvertedOpportunityId +
                ', tokens=' + tokenCount
            );

            if (
                deliveryTokens == null ||
                deliveryTokens.isEmpty()
            ) {

                System.debug(
                    LoggingLevel.WARN,
                    'CONVERSION PUSH: No active tokens for ' +
                    projectLabel +
                    ', Lead=' + eventLead.Id
                );

                continue;
            }

            // Deduplication occurs within this project's
            // conversion event, not across different projects.
            for (String token : deliveryTokens) {

                if (
                    attemptedCount >= MAX_PUSH_ATTEMPTS ||
                    Limits.getCallouts() >=
                        Limits.getLimitCallouts() - 2
                ) {
                    limitReached = true;
                    break;
                }

                attemptedCount++;

                try {

                    FirebasePushService.sendPushToToken(
                        token,
                        title,
                        body,
                        payload
                    );

                    successfulCount++;

                    System.debug(
                        LoggingLevel.INFO,
                        'CONVERSION PUSH ACCEPTED: ' +
                        projectLabel +
                        ', Lead=' + eventLead.Id +
                        ', Account=' + accountLeadId
                    );

                } catch (Exception ex) {

                    failedCount++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'CONVERSION PUSH FAILED: ' +
                        projectLabel +
                        ', Lead=' + eventLead.Id +
                        ', Error=' + ex.getMessage()
                    );
                }
            }

            if (limitReached) {
                System.debug(
                    LoggingLevel.WARN,
                    'CONVERSION PUSH: Processing limit reached. ' +
                    'Remaining notifications not attempted.'
                );
                break;
            }
        }

        // =====================================================
        // 9. FINAL DEBUG SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            'CONVERSION PUSH COMPLETE. ' +
            'Attempted=' + attemptedCount +
            ', Successful=' + successfulCount +
            ', Failed=' + failedCount
        );
    }

    // =========================================================
    // 10. RESOLVE ORIGINAL ACCOUNT LEAD
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

            Id originalLeadId =
                (Id) projectLead.Portal_Account_Key__c.trim();

            if (
                originalLeadId.getSObjectType() ==
                    Lead.SObjectType
            ) {
                return originalLeadId;
            }

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.WARN,
                'CONVERSION PUSH: Invalid account key for ' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }
}