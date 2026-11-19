public without sharing class ArchitectureManagerApprovedClientPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> architectureDesignIds;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public ArchitectureManagerApprovedClientPushJob(
        Set<Id> architectureDesignIds
    ) {
        this.architectureDesignIds =
            architectureDesignIds == null
                ? new Set<Id>()
                : new Set<Id>(architectureDesignIds);
    }

    public void execute(QueueableContext context) {

        if (architectureDesignIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'MANAGER PUSH: No Architecture Design IDs.'
            );
            return;
        }

        System.debug(
            LoggingLevel.INFO,
            'MANAGER APPROVAL PUSH STARTED. Job=' +
            context.getJobId()
        );

        // =====================================================
        // 1. GET APPROVED ARCHITECTURE DESIGNS
        // =====================================================

        List<Architecture_Design__c> designs = [
            SELECT
                Id,
                Name,
                Opportunity__c,
                Manager_Approval__c,
                Architect_Approved_Date__c
            FROM Architecture_Design__c
            WHERE Id IN :architectureDesignIds
              AND Manager_Approval__c = true
              AND Opportunity__c != null
              AND Architect_Approved_Date__c != null
            ORDER BY Id
        ];

        if (designs.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'MANAGER PUSH: No approved designs.'
            );
            return;
        }

        Set<Id> opportunityIds = new Set<Id>();

        for (Architecture_Design__c design : designs) {
            opportunityIds.add(design.Opportunity__c);
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

        List<Lead> convertedLeads = [
            SELECT
                Id,
                IsConverted,
                ConvertedOpportunityId,
                ConvertedContactId,
                Portal_Account_Key__c,
                CreatedDate
            FROM Lead
            WHERE IsConverted = true
              AND ConvertedOpportunityId IN :opportunityIds
              AND ConvertedContactId != null
            ORDER BY CreatedDate ASC, Id ASC
        ];

        for (Lead prospect : convertedLeads) {

            if (
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

            originalAccountLeadIds.add(
                accountLeadId
            );
        }

        if (leadByOpportunity.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'MANAGER PUSH: No converted Leads found.'
            );
            return;
        }

        // =====================================================
        // 3. GET ALL LEADS RELATED TO ORIGINAL ACCOUNT
        // =====================================================

        Set<String> accountKeys =
            new Set<String>();

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

        Set<Id> allProjectLeadIds =
            new Set<Id>();

        Map<Id, Set<Id>> contactIdsByAccount =
            new Map<Id, Set<Id>>();

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        for (Id accountId : originalAccountLeadIds) {

            contactIdsByAccount.put(
                accountId,
                new Set<Id>()
            );

            tokensByAccount.put(
                accountId,
                new Set<String>()
            );

            projectCountByAccount.put(
                accountId,
                0
            );
        }

        // =====================================================
        // 4. ASSIGN PROJECT 1, PROJECT 2, PROJECT 3...
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

            allProjectLeadIds.add(
                projectLead.Id
            );

            // Corrected: projectNumber instead of number.
            Integer projectNumber =
                projectCountByAccount.get(accountId) + 1;

            projectCountByAccount.put(
                accountId,
                projectNumber
            );

            projectLabelByLead.put(
                projectLead.Id,
                'Project ' +
                String.valueOf(projectNumber)
            );

            if (
                projectLead.ConvertedContactId != null
            ) {
                contactIdsByAccount.get(accountId).add(
                    projectLead.ConvertedContactId
                );
            }
        }

        // =====================================================
        // 5. GET PROSPECT TOKENS FROM ALL RELATED LEADS
        // =====================================================

        Integer prospectRecordsFound = 0;

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

            prospectRecordsFound++;

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
        // 6. GET CONTACT TOKENS FOR ALL CONVERTED PROJECTS
        // =====================================================

        Set<Id> allContactIds =
            new Set<Id>();

        Map<Id, Set<Id>> accountsByContact =
            new Map<Id, Set<Id>>();

        for (Id accountId : contactIdsByAccount.keySet()) {

            for (
                Id contactId :
                contactIdsByAccount.get(accountId)
            ) {

                allContactIds.add(contactId);

                if (
                    !accountsByContact.containsKey(contactId)
                ) {
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

        Integer mobileRecordsFound = 0;

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

                mobileRecordsFound++;

                if (
                    device.Contact__c == null ||
                    String.isBlank(device.FCM_Token__c)
                ) {
                    continue;
                }

                Set<Id> linkedAccounts =
                    accountsByContact.get(
                        device.Contact__c
                    );

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

        System.debug(
            LoggingLevel.INFO,
            'MANAGER PUSH: Prospect token records=' +
            prospectRecordsFound +
            ', Mobile token records=' +
            mobileRecordsFound
        );

        // =====================================================
        // 7. SEND PROJECT-SPECIFIC MANAGER APPROVAL PUSH
        // =====================================================

        Integer totalAttempts = 0;
        Integer successfulRequests = 0;
        Integer failedRequests = 0;

        Boolean reachedLimit = false;

        for (Architecture_Design__c design : designs) {

            Lead prospect =
                leadByOpportunity.get(
                    design.Opportunity__c
                );

            if (prospect == null) {

                System.debug(
                    LoggingLevel.WARN,
                    'MANAGER PUSH: Converted Lead missing. ' +
                    'Design=' + design.Id
                );

                continue;
            }

            Id accountLeadId =
                accountByEventLead.get(
                    prospect.Id
                );

            if (accountLeadId == null) {
                continue;
            }

            String projectLabel =
                projectLabelByLead.containsKey(
                    prospect.Id
                )
                    ? projectLabelByLead.get(prospect.Id)
                    : 'Your project';

            Set<String> candidateTokens =
                tokensByAccount.get(
                    accountLeadId
                );

            if (
                candidateTokens == null ||
                candidateTokens.isEmpty()
            ) {

                System.debug(
                    LoggingLevel.WARN,
                    'MANAGER PUSH: No active device tokens. ' +
                    'Lead=' + prospect.Id +
                    ', Account=' + accountLeadId
                );

                continue;
            }

            // =================================================
            // 8. PREPARE NOTIFICATION TITLE AND BODY
            // =================================================

            String title =
                'Arelia - ' +
                projectLabel +
                ': Architecture Design Approved';

            String body =
                'Good news! Your architecture design has been ' +
                'approved by our manager. ' +
                'Tap to view the approved design.';

            String notificationId =
                'ARCHITECTURE_MANAGER_APPROVED:' +
                String.valueOf(
                    design.Id
                );

            Map<String, String> payload =
                new Map<String, String>{

                    'recipientType' =>
                        'prospect',

                    'notificationType' =>
                        'ARCHITECTURE_MANAGER_APPROVED',

                    'type' =>
                        'ARCHITECTURE_MANAGER_APPROVED',

                    'actionType' =>
                        'OPEN_ARCHITECTURE_DESIGN',

                    'route' =>
                        'prospect_architecture_design',

                    // Actual project Lead.
                    'leadId' =>
                        String.valueOf(prospect.Id),

                    // Original customer Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    // Converted Contact of actual project.
                    'contactId' =>
                        String.valueOf(
                            prospect.ConvertedContactId
                        ),

                    // Opportunity belonging to actual project.
                    'opportunityId' =>
                        String.valueOf(
                            design.Opportunity__c
                        ),

                    // Approved Architecture Design record.
                    'designId' =>
                        String.valueOf(design.Id),

                    'recordId' =>
                        String.valueOf(design.Id),

                    'id' =>
                        notificationId,

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

            if (
                projectLabel.startsWith('Project ')
            ) {

                payload.put(
                    'projectNumber',
                    projectLabel.substring(8)
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'MANAGER MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', Design=' + design.Id +
                ', Lead=' + prospect.Id +
                ', Account=' + accountLeadId +
                ', Tokens=' + candidateTokens.size()
            );

            // =================================================
            // 9. SEND USING EXISTING FIREBASE SERVICE
            // =================================================

            for (String token : candidateTokens) {

                if (String.isBlank(token)) {
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
                        'MANAGER PUSH: Callout safety limit reached.'
                    );

                    break;
                }

                totalAttempts++;

                try {

                    FirebasePushService.sendPushToToken(
                        token,
                        title,
                        body,
                        payload
                    );

                    successfulRequests++;

                    System.debug(
                        LoggingLevel.INFO,
                        'MANAGER APPROVAL PUSH SENT. ' +
                        'Project=' + projectLabel +
                        ', Design=' + design.Id +
                        ', Lead=' + prospect.Id +
                        ', Account=' + accountLeadId
                    );

                } catch (Exception ex) {

                    failedRequests++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'MANAGER APPROVAL PUSH FAILED. ' +
                        'Design=' + design.Id +
                        ', Lead=' + prospect.Id +
                        ', Error=' + ex.getMessage()
                    );
                }
            }

            if (reachedLimit) {
                break;
            }
        }

        // =====================================================
        // 10. FINAL EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '=== MANAGER APPROVAL CLIENT PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Architecture Designs=' +
            designs.size()
        );

        System.debug(
            LoggingLevel.INFO,
            'Prospect token records=' +
            prospectRecordsFound
        );

        System.debug(
            LoggingLevel.INFO,
            'Mobile token records=' +
            mobileRecordsFound
        );

        System.debug(
            LoggingLevel.INFO,
            'FCM attempts=' +
            totalAttempts
        );

        System.debug(
            LoggingLevel.INFO,
            'FCM completed requests=' +
            successfulRequests
        );

        System.debug(
            LoggingLevel.INFO,
            'FCM failed requests=' +
            failedRequests
        );

        System.debug(
            LoggingLevel.INFO,
            'Callout limit reached=' +
            reachedLimit
        );

        System.debug(
            LoggingLevel.INFO,
            'MANAGER APPROVAL CLIENT PUSH JOB FINISHED.'
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
                'MANAGER PUSH: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }
}