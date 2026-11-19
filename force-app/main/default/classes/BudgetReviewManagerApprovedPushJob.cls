public without sharing class BudgetReviewManagerApprovedPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> opportunityIds;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public BudgetReviewManagerApprovedPushJob(
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
                'BUDGET MANAGER: No Opportunity IDs.'
            );
            return;
        }

        // =====================================================
        // 1. GET MANAGER-APPROVED OPPORTUNITIES
        // =====================================================

        List<Opportunity> opportunities = [
            SELECT
                Id,
                Name,
                Budget_Review_Status__c,
                Budget_Review_Approved_Date__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND Budget_Review_Status__c = 'Manager Approved'
              AND Budget_Review_Approved_Date__c != null
            ORDER BY Id
        ];

        if (opportunities.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'BUDGET MANAGER: No approved Opportunities.'
            );
            return;
        }

        Set<Id> eligibleOpportunityIds = new Set<Id>();

        for (Opportunity opp : opportunities) {
            eligibleOpportunityIds.add(opp.Id);
        }

        // =====================================================
        // 2. GET CONVERTED LEADS FOR EACH OPPORTUNITY
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
              AND ConvertedOpportunityId IN :eligibleOpportunityIds
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
                'BUDGET MANAGER: No converted Leads found.'
            );
            return;
        }

        // =====================================================
        // 3. GET ALL LEADS BELONGING TO EACH CUSTOMER
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

        Map<Id, Set<Id>> contactsByAccount =
            new Map<Id, Set<Id>>();

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        Set<Id> allProjectLeadIds =
            new Set<Id>();

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
        // 4. ASSIGN PROJECT NUMBERS
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
        // 5. FETCH PROSPECT TOKENS ACCOUNT-WIDE
        // =====================================================

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

            tokensByAccount.get(accountId).add(
                device.FCM_Token__c.trim()
            );
        }

        // =====================================================
        // 6. FETCH CONVERTED CONTACT TOKENS ACCOUNT-WIDE
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

                accountsByContact.get(contactId).add(
                    accountId
                );
            }
        }

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

                for (Id accountId : linkedAccounts) {
                    tokensByAccount.get(accountId).add(
                        device.FCM_Token__c.trim()
                    );
                }
            }
        }

        // =====================================================
        // 7. PREPARE MANAGER APPROVAL NOTIFICATIONS
        // =====================================================

        List<Mobile_Notification__c> notificationHistory =
            new List<Mobile_Notification__c>();

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
                    'BUDGET MANAGER: No Lead for Opportunity=' +
                    opp.Id
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

            // =================================================
            // 8. PROJECT-SPECIFIC NOTIFICATION
            // =================================================

            String title =
                'Arelia - ' + projectLabel +
                ': Budget Approved';

            String body =
                'Your budget has been approved by the Arelia Team. ' +
                'Tap to view the updated details.';

            // Preserve existing notification history behavior.
            if (prospect.ConvertedContactId != null) {

                Mobile_Notification__c notificationRec =
                    new Mobile_Notification__c();

                notificationRec.Contact__c =
                    prospect.ConvertedContactId;

                notificationRec.Title__c = title;

                notificationRec.Message__c = body;

                notificationRec.Notification_Type__c =
                    'BUDGET_REVIEW_MANAGER_APPROVED';

                notificationRec.Related_Record_Id__c =
                    String.valueOf(opp.Id);

                notificationRec.Read__c = false;

                notificationRec.Sent_On__c = System.now();

                notificationHistory.add(notificationRec);
            }

            Set<String> candidateTokens =
                tokensByAccount.get(accountLeadId);

            if (
                candidateTokens == null ||
                candidateTokens.isEmpty()
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'BUDGET MANAGER: No active device tokens. ' +
                    'Lead=' + prospect.Id +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            // =================================================
            // 9. FLUTTER NAVIGATION PAYLOAD
            // =================================================

            String notificationType =
                'BUDGET_REVIEW_MANAGER_APPROVED';

            Map<String, String> payload =
                new Map<String, String>{

                    'recipientType' => 'prospect',

                    'notificationType' => notificationType,

                    'type' => notificationType,

                    'actionType' => 'OPEN_BUDGET_REVIEW',

                    'route' => 'prospect_budget_review',

                    // Exact project Lead.
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

                    // Exact Opportunity being approved.
                    'opportunityId' =>
                        String.valueOf(opp.Id),

                    'recordId' =>
                        String.valueOf(opp.Id),

                    'id' =>
                        notificationType + ':' +
                        String.valueOf(opp.Id),

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
                'BUDGET MANAGER MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', Opportunity=' + opp.Id +
                ', Lead=' + prospect.Id +
                ', Account=' + accountLeadId +
                ', Devices=' + candidateTokens.size()
            );

            // =================================================
            // 10. SEND ONE NOTIFICATION PER UNIQUE DEVICE
            // =================================================

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
                        'BUDGET MANAGER: Callout safety limit reached.'
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
                        'BUDGET MANAGER PUSH COMPLETED. ' +
                        'Project=' + projectLabel +
                        ', Opportunity=' + opp.Id +
                        ', Lead=' + prospect.Id
                    );

                } catch (Exception ex) {

                    failed++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'BUDGET MANAGER PUSH FAILED. ' +
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
        // 11. SAVE EXISTING NOTIFICATION HISTORY
        // =====================================================

        // DML runs after all Firebase callouts.
        Integer historySaved = 0;
        Integer historyFailed = 0;

        if (!notificationHistory.isEmpty()) {

            Database.SaveResult[] results =
                Database.insert(
                    notificationHistory,
                    false
                );

            for (Integer i = 0; i < results.size(); i++) {

                if (results[i].isSuccess()) {
                    historySaved++;
                } else {

                    historyFailed++;

                    for (
                        Database.Error err :
                        results[i].getErrors()
                    ) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'BUDGET HISTORY SAVE FAILED: ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }

        // =====================================================
        // 12. EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '=== BUDGET MANAGER MULTI-PROJECT PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Opportunities=' + opportunities.size() +
            ', ProspectTokens=' + prospectTokenRecords +
            ', MobileTokens=' + mobileTokenRecords +
            ', Attempts=' + attempts +
            ', Completed=' + completed +
            ', Failed=' + failed +
            ', HistorySaved=' + historySaved +
            ', HistoryFailed=' + historyFailed +
            ', CalloutLimitReached=' + limitReached
        );
    }

    // =====================================================
    // 13. RESOLVE ORIGINAL CUSTOMER LEAD
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
                'BUDGET MANAGER: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }
}