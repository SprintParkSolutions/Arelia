public without sharing class ClientAgreementPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> opportunityIds;
    private Boolean signedNotification;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public ClientAgreementPushJob(
        Set<Id> opportunityIds
    ) {
        this.opportunityIds = opportunityIds == null
            ? new Set<Id>()
            : new Set<Id>(opportunityIds);
        this.signedNotification = false;
    }

    // New overload for Client Agreement Signed notifications.
    // Existing callers using the one-argument constructor are unchanged.
    public ClientAgreementPushJob(
        Set<Id> opportunityIds,
        Boolean signedNotification
    ) {
        this.opportunityIds = opportunityIds == null
            ? new Set<Id>()
            : new Set<Id>(opportunityIds);
        this.signedNotification = signedNotification == true;
    }

    public void execute(QueueableContext context) {

        if (opportunityIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'CLIENT AGREEMENT: No Opportunity IDs.'
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
                Client_Agreement_Sent__c,
                Client_Agreement_Signed__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND (
                  Client_Agreement_Sent__c = true
                  OR Client_Agreement_Signed__c = true
              )
            ORDER BY Id
        ];

        if (opportunities.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'CLIENT AGREEMENT: No eligible Opportunities.'
            );
            return;
        }

        Set<Id> eligibleOpportunityIds = new Set<Id>();

        List<Opportunity> selectedOpportunities =
            new List<Opportunity>();

        for (Opportunity opp : opportunities) {
            if (signedNotification) {
                if (opp.Client_Agreement_Signed__c != true) continue;
            } else {
                if (opp.Client_Agreement_Sent__c != true) continue;
            }
            eligibleOpportunityIds.add(opp.Id);
            selectedOpportunities.add(opp);
        }

        if (selectedOpportunities.isEmpty()) {
            System.debug('CLIENT AGREEMENT: No matching event records.');
            return;
        }

        // =====================================================
        // 2. FIND CONVERTED LEADS FOR EACH OPPORTUNITY
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
                'CLIENT AGREEMENT: No converted Leads found.'
            );
            return;
        }

        // =====================================================
        // 3. FIND ALL LEADS FOR EACH CUSTOMER ACCOUNT
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

        Set<Id> allProjectLeadIds = new Set<Id>();

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
        // 5. GET ACTIVE PROSPECT TOKENS ACCOUNT-WIDE
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
        // 6. GET ACTIVE CONTACT TOKENS ACCOUNT-WIDE
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

        // Project ID is included to enable correct project navigation.
        // Project_Name__c is this org's Opportunity lookup on Project__c.
        Map<Id, Id> projectByOpportunity = new Map<Id, Id>();
        for (Project__c projectRec : [
            SELECT Id, Project_Name__c
            FROM Project__c
            WHERE Project_Name__c IN :eligibleOpportunityIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!projectByOpportunity.containsKey(projectRec.Project_Name__c)) {
                projectByOpportunity.put(projectRec.Project_Name__c, projectRec.Id);
            }
        }

        // =====================================================
        // 7. SEND PROJECT-SPECIFIC CLIENT AGREEMENT PUSH
        // =====================================================

        Integer attempts = 0;
        Integer completed = 0;
        Integer failed = 0;

        Boolean limitReached = false;

        for (Opportunity opp : selectedOpportunities) {

            Lead prospect =
                leadByOpportunity.get(opp.Id);

            if (prospect == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'CLIENT AGREEMENT: No Lead for Opportunity=' +
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

            Set<String> candidateTokens =
                tokensByAccount.get(accountLeadId);

            if (
                candidateTokens == null ||
                candidateTokens.isEmpty()
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'CLIENT AGREEMENT: No active device token. ' +
                    'Lead=' + prospect.Id +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            // =================================================
            // 8. PROJECT-SPECIFIC TITLE AND MESSAGE
            // =================================================

            String title =
                'Arelia - ' + projectLabel +
                ': Client Agreement Ready';

            // Preserve existing notification body.
            String body =
                'Your client agreement has been sent to your email. ' +
                'Please review and complete the agreement.';

            String notificationType =
                'CLIENT_AGREEMENT_SENT';

            if (signedNotification) {
                title = 'Arelia - ' + projectLabel +
                    ': Client Agreement Signed';
                body = 'Your Client Agreement has been successfully signed. ' +
                    'Please check your registered email address to download ' +
                    'a copy of the signed agreement.';
                notificationType = 'CLIENT_AGREEMENT_SIGNED';
            }

            // =================================================
            // 9. EXISTING FLUTTER NAVIGATION PAYLOAD
            // =================================================

            Map<String, String> payload =
                new Map<String, String>{

                    'recipientType' =>
                        'prospect',

                    'notificationType' =>
                        notificationType,

                    'type' =>
                        notificationType,

                    'actionType' =>
                        'OPEN_CLIENT_AGREEMENT',

                    'route' =>
                        'client_agreement',

                    // Actual project Lead.
                    'leadId' =>
                        String.valueOf(prospect.Id),

                    // Original customer login Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    // Converted Contact of this project.
                    'contactId' =>
                        prospect.ConvertedContactId == null
                            ? ''
                            : String.valueOf(
                                prospect.ConvertedContactId
                            ),

                    // Exact project's Opportunity.
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

            if (projectByOpportunity.containsKey(opp.Id)) {
                payload.put('projectId', String.valueOf(
                    projectByOpportunity.get(opp.Id)
                ));
            }

            if (projectLabel.startsWith('Project ')) {
                payload.put(
                    'projectNumber',
                    projectLabel.substring(8)
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'CLIENT AGREEMENT MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', Opportunity=' + opp.Id +
                ', Lead=' + prospect.Id +
                ', Account=' + accountLeadId +
                ', Devices=' + candidateTokens.size()
            );

            // =================================================
            // 10. SEND ONE NOTIFICATION PER UNIQUE DEVICE
            // =================================================

            // Set<String> already removes duplicate FCM
            // tokens registered under multiple records.

            for (String token : candidateTokens) {

                if (String.isBlank(token)) {
                    continue;
                }

                // Leave headroom for Firebase authentication
                // and other callouts inside FirebasePushService.
                if (
                    attempts >= MAX_PUSH_ATTEMPTS ||
                    Limits.getCallouts() >=
                        Limits.getLimitCallouts() - 2
                ) {
                    limitReached = true;

                    System.debug(
                        LoggingLevel.WARN,
                        'CLIENT AGREEMENT: Callout safety limit reached.'
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
                        'CLIENT AGREEMENT PUSH COMPLETED. ' +
                        'Project=' + projectLabel +
                        ', Opportunity=' + opp.Id +
                        ', Lead=' + prospect.Id
                    );

                } catch (Exception ex) {

                    failed++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'CLIENT AGREEMENT PUSH FAILED. ' +
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
        // 11. FINAL EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '=== CLIENT AGREEMENT MULTI-PROJECT PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Opportunities=' + selectedOpportunities.size() +
            ', ProspectTokens=' + prospectTokenRecords +
            ', MobileTokens=' + mobileTokenRecords +
            ', Attempts=' + attempts +
            ', Completed=' + completed +
            ', Failed=' + failed +
            ', CalloutLimitReached=' + limitReached
        );
    }

    // =====================================================
    // 12. RESOLVE ORIGINAL CUSTOMER LEAD
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
                'CLIENT AGREEMENT: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }
}