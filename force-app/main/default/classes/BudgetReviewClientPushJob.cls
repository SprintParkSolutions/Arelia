public without sharing class BudgetReviewClientPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> opportunityIds;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public BudgetReviewClientPushJob(
        Set<Id> opportunityIds
    ) {
        this.opportunityIds = opportunityIds == null
            ? new Set<Id>()
            : new Set<Id>(opportunityIds);
    }

    public void execute(QueueableContext context) {

        if (opportunityIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'BUDGET REVIEW PUSH: No Opportunity IDs.'
            );
            return;
        }

        // =====================================================
        // 1. GET OPPORTUNITIES SENT FOR CLIENT APPROVAL
        // =====================================================

        List<Opportunity> opportunities = [
            SELECT
                Id,
                Name,
                Budget_Review_Status__c,
                Budget_Review_Manager_Remarks__c,
                Budget_Review_Client_Remarks__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND Budget_Review_Status__c =
                  'Sent for Client Approval'
            ORDER BY Id
        ];

        if (opportunities.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'BUDGET REVIEW PUSH: No eligible Opportunities.'
            );
            return;
        }

        Set<Id> eligibleOpportunityIds = new Set<Id>();

        for (Opportunity opp : opportunities) {
            eligibleOpportunityIds.add(opp.Id);
        }

        // =====================================================
        // 2. FIND CONVERTED PROJECT LEADS
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
                'BUDGET REVIEW PUSH: No converted Leads.'
            );
            return;
        }

        // =====================================================
        // 3. FETCH ALL PROJECT LEADS UNDER EACH ACCOUNT
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

        Set<Id> allProjectLeadIds = new Set<Id>();

        Map<Id, Set<Id>> contactsByAccount =
            new Map<Id, Set<Id>>();

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        for (Id accountId : originalAccountLeadIds) {

            projectCountByAccount.put(accountId, 0);

            contactsByAccount.put(
                accountId,
                new Set<Id>()
            );

            tokensByAccount.put(
                accountId,
                new Set<String>()
            );
        }

        // =====================================================
        // 4. ASSIGN PROJECT 1, PROJECT 2, PROJECT 3...
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
                contactsByAccount.get(accountId).add(
                    projectLead.ConvertedContactId
                );
            }
        }

        // =====================================================
        // 5. GET PROSPECT TOKENS FOR ALL PROJECT LEADS
        // =====================================================

        Map<String, Set<Id>> prospectIdsByToken =
            new Map<String, Set<Id>>();

        Integer prospectTokenRecords = 0;

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

            prospectTokenRecords++;

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

            String fcmToken =
                device.FCM_Token__c.trim();

            tokensByAccount.get(accountId).add(fcmToken);

            if (!prospectIdsByToken.containsKey(fcmToken)) {
                prospectIdsByToken.put(
                    fcmToken,
                    new Set<Id>()
                );
            }

            prospectIdsByToken.get(fcmToken).add(device.Id);
        }

        // =====================================================
        // 6. GET MOBILE TOKENS FOR RELATED CONTACTS
        // =====================================================

        Set<Id> allContactIds = new Set<Id>();

        Map<Id, Set<Id>> accountsByContact =
            new Map<Id, Set<Id>>();

        for (Id accountId : contactsByAccount.keySet()) {

            for (
                Id contactId :
                contactsByAccount.get(accountId)
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

        Map<String, Set<Id>> mobileIdsByToken =
            new Map<String, Set<Id>>();

        Integer mobileTokenRecords = 0;

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

                mobileTokenRecords++;

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

                String fcmToken =
                    device.FCM_Token__c.trim();

                for (Id accountId : linkedAccounts) {
                    tokensByAccount.get(accountId).add(
                        fcmToken
                    );
                }

                if (!mobileIdsByToken.containsKey(fcmToken)) {
                    mobileIdsByToken.put(
                        fcmToken,
                        new Set<Id>()
                    );
                }

                mobileIdsByToken.get(fcmToken).add(device.Id);
            }
        }

        // =====================================================
        // 7. PREPARE PROJECT-SPECIFIC NOTIFICATIONS
        // =====================================================

        Integer attempts = 0;
        Integer completed = 0;
        Integer failed = 0;

        Boolean limitReached = false;

        Set<String> invalidTokens = new Set<String>();

        Set<Id> staleMobileTokenIds = new Set<Id>();
        Set<Id> staleProspectTokenIds = new Set<Id>();

        for (Opportunity opportunity : opportunities) {

            Lead prospect =
                leadByOpportunity.get(opportunity.Id);

            if (prospect == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'BUDGET REVIEW PUSH: No Lead. Opportunity=' +
                    opportunity.Id
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
                    'BUDGET REVIEW PUSH: No active account tokens. ' +
                    'Lead=' + prospect.Id +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            String title =
                'Arelia - ' + projectLabel +
                ': Budget Review Ready';

            // Preserve your existing notification message.
            String body =
                'Your project budget is ready for your review. ' +
                'Tap to view and submit your response.';

            String notificationType =
                'BUDGET_REVIEW_SENT';

            Map<String, String> payload =
                new Map<String, String>{

                    'recipientType' => 'prospect',

                    'notificationType' => notificationType,

                    'type' => notificationType,

                    'actionType' => 'OPEN_BUDGET_REVIEW',

                    'route' => 'prospect_budget_review',

                    // Actual converted project Lead.
                    'leadId' =>
                        String.valueOf(prospect.Id),

                    // Original login Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    'contactId' =>
                        prospect.ConvertedContactId == null
                            ? ''
                            : String.valueOf(
                                prospect.ConvertedContactId
                            ),

                    // Exact project's Opportunity.
                    'opportunityId' =>
                        String.valueOf(opportunity.Id),

                    'recordId' =>
                        String.valueOf(opportunity.Id),

                    'id' =>
                        notificationType + ':' +
                        String.valueOf(opportunity.Id),

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
                'BUDGET REVIEW MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', Lead=' + prospect.Id +
                ', Account=' + accountLeadId +
                ', Opportunity=' + opportunity.Id +
                ', Devices=' + candidateTokens.size()
            );

            // =================================================
            // 8. SEND TO UNIQUE DEVICES FOR THIS PROJECT EVENT
            // =================================================

            for (String token : candidateTokens) {

                if (
                    String.isBlank(token) ||
                    invalidTokens.contains(token)
                ) {
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
                        'BUDGET REVIEW PUSH: Callout safety limit reached.'
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
                        'BUDGET REVIEW PUSH REQUEST COMPLETED. ' +
                        'Project=' + projectLabel +
                        ', Opportunity=' + opportunity.Id +
                        ', Lead=' + prospect.Id
                    );

                } catch (Exception ex) {

                    failed++;

                    String errorMessage =
                        ex.getMessage() == null
                            ? ''
                            : ex.getMessage();

                    System.debug(
                        LoggingLevel.ERROR,
                        'BUDGET REVIEW PUSH FAILED. ' +
                        'Opportunity=' + opportunity.Id +
                        ', Error=' + errorMessage
                    );

                    if (isInvalidFirebaseToken(errorMessage)) {

                        invalidTokens.add(token);

                        if (mobileIdsByToken.containsKey(token)) {
                            staleMobileTokenIds.addAll(
                                mobileIdsByToken.get(token)
                            );
                        }

                        if (prospectIdsByToken.containsKey(token)) {
                            staleProspectTokenIds.addAll(
                                prospectIdsByToken.get(token)
                            );
                        }
                    }
                }
            }

            if (limitReached) {
                break;
            }
        }

        // =====================================================
        // 9. DEACTIVATE INVALID TOKENS AFTER CALLOUTS
        // =====================================================

        if (!staleMobileTokenIds.isEmpty()) {

            List<Mobile_Device_Token__c> updates =
                new List<Mobile_Device_Token__c>();

            for (Id tokenId : staleMobileTokenIds) {
                updates.add(
                    new Mobile_Device_Token__c(
                        Id = tokenId,
                        Active__c = false
                    )
                );
            }

            Database.update(updates, false);
        }

        if (!staleProspectTokenIds.isEmpty()) {

            List<Prospect_Device_Token__c> updates =
                new List<Prospect_Device_Token__c>();

            for (Id tokenId : staleProspectTokenIds) {
                updates.add(
                    new Prospect_Device_Token__c(
                        Id = tokenId,
                        Active__c = false
                    )
                );
            }

            Database.update(updates, false);
        }

        // =====================================================
        // 10. EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '=== BUDGET REVIEW MULTI-PROJECT PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Opportunities=' + opportunities.size() +
            ', ProspectTokens=' + prospectTokenRecords +
            ', MobileTokens=' + mobileTokenRecords +
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
                'BUDGET REVIEW PUSH: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }

    // =====================================================
    // 12. DETECT INVALID FIREBASE TOKENS
    // =====================================================

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