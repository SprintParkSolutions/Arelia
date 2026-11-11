public without sharing class LeadProjectApprovalPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> leadIds;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public LeadProjectApprovalPushJob(Set<Id> leadIds) {
        this.leadIds = leadIds == null
            ? new Set<Id>()
            : new Set<Id>(leadIds);
    }

    public void execute(QueueableContext context) {

        if (leadIds.isEmpty()) {
            return;
        }

        // =====================================================
        // 1. GET APPROVED, UNCONVERTED LEADS
        // =====================================================

        List<Lead> approvedLeads = [
            SELECT
                Id,
                Approval_Status__c,
                IsConverted,
                Portal_Account_Key__c,
                CreatedDate
            FROM Lead
            WHERE Id IN :leadIds
              AND IsConverted = false
              AND Approval_Status__c = 'Approved'
            ORDER BY CreatedDate ASC, Id ASC
        ];

        if (approvedLeads.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PROJECT APPROVAL: No eligible Leads.'
            );
            return;
        }

        // =====================================================
        // 2. FIND ORIGINAL CUSTOMER ACCOUNT LEAD
        // =====================================================

        Map<Id, Id> accountByApprovedLead =
            new Map<Id, Id>();

        Set<Id> originalAccountLeadIds =
            new Set<Id>();

        for (Lead approvedLead : approvedLeads) {

            Id accountLeadId =
                resolveOriginalLeadId(approvedLead);

            accountByApprovedLead.put(
                approvedLead.Id,
                accountLeadId
            );

            originalAccountLeadIds.add(accountLeadId);
        }

        // =====================================================
        // 3. GET ALL RELATED PROJECT LEADS
        // =====================================================

        Set<String> accountKeys =
            new Set<String>();

        for (Id accountLeadId : originalAccountLeadIds) {
            accountKeys.add(
                String.valueOf(accountLeadId)
            );
        }

        List<Lead> projectLeads = [
            SELECT
                Id,
                Portal_Account_Key__c,
                ConvertedContactId,
                CreatedDate
            FROM Lead
            WHERE Id IN :originalAccountLeadIds
               OR Portal_Account_Key__c IN :accountKeys
            ORDER BY CreatedDate ASC, Id ASC
        ];

        Map<Id, Id> accountByProjectLead =
            new Map<Id, Id>();

        Map<Id, Integer> projectNumberByLead =
            new Map<Id, Integer>();

        Map<Id, Set<Id>> leadIdsByAccount =
            new Map<Id, Set<Id>>();

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        Map<Id, Integer> projectCounterByAccount =
            new Map<Id, Integer>();

        for (Id accountLeadId : originalAccountLeadIds) {

            leadIdsByAccount.put(
                accountLeadId,
                new Set<Id>()
            );

            tokensByAccount.put(
                accountLeadId,
                new Set<String>()
            );

            projectCounterByAccount.put(
                accountLeadId,
                0
            );
        }

        // =====================================================
        // 4. ASSIGN PROJECT 1, PROJECT 2, PROJECT 3...
        // =====================================================

        for (Lead projectLead : projectLeads) {

            Id accountLeadId =
                resolveOriginalLeadId(projectLead);

            if (
                !originalAccountLeadIds.contains(
                    accountLeadId
                )
            ) {
                continue;
            }

            accountByProjectLead.put(
                projectLead.Id,
                accountLeadId
            );

            leadIdsByAccount.get(accountLeadId).add(
                projectLead.Id
            );

            Integer projectNumber =
                projectCounterByAccount.get(
                    accountLeadId
                ) + 1;

            projectCounterByAccount.put(
                accountLeadId,
                projectNumber
            );

            projectNumberByLead.put(
                projectLead.Id,
                projectNumber
            );
        }

        // =====================================================
        // 5. FETCH ACTIVE PROSPECT DEVICE TOKENS
        // =====================================================

        Set<Id> allProjectLeadIds =
            new Set<Id>();

        for (Id accountLeadId : leadIdsByAccount.keySet()) {
            allProjectLeadIds.addAll(
                leadIdsByAccount.get(accountLeadId)
            );
        }

        Integer tokenRecordsFound = 0;

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

            if (
                device.Prospect_Lead__c == null ||
                String.isBlank(device.FCM_Token__c)
            ) {
                continue;
            }

            Id accountLeadId =
                accountByProjectLead.get(
                    device.Prospect_Lead__c
                );

            if (
                accountLeadId == null ||
                !tokensByAccount.containsKey(
                    accountLeadId
                )
            ) {
                continue;
            }

            String fcmToken =
                device.FCM_Token__c.trim();

            tokensByAccount.get(accountLeadId).add(
                fcmToken
            );

            tokenRecordsFound++;
        }

        // =====================================================
        // 6. SEND PROJECT APPROVAL NOTIFICATIONS
        // =====================================================

        Integer attempts = 0;
        Integer completed = 0;
        Integer failed = 0;

        Boolean limitReached = false;

        for (Lead approvedLead : approvedLeads) {

            Id accountLeadId =
                accountByApprovedLead.get(
                    approvedLead.Id
                );

            if (accountLeadId == null) {
                continue;
            }

            Set<String> candidateTokens =
                tokensByAccount.get(accountLeadId);

            if (
                candidateTokens == null ||
                candidateTokens.isEmpty()
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROJECT APPROVAL: No active account token. ' +
                    'Lead=' + approvedLead.Id +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            Integer projectNumber =
                projectNumberByLead.get(
                    approvedLead.Id
                );

            String projectLabel =
                projectNumber == null
                    ? 'Your Project'
                    : 'Project ' +
                        String.valueOf(projectNumber);

            // =================================================
            // 7. PROJECT-SPECIFIC NOTIFICATION TITLE
            // =================================================

            String title =
                'Arelia - ' + projectLabel +
                ': Project Details Approved';

            // Preserve existing message.
            String body =
                'Your project details have been approved ' +
                'by the Arelia team.';

            String notificationType =
                'PROJECT_DETAILS_APPROVED';

            // =================================================
            // 8. FLUTTER NOTIFICATION PAYLOAD
            // =================================================

            Map<String, String> dataPayload =
                new Map<String, String>{

                    'recipientType' =>
                        'prospect',

                    'notificationType' =>
                        notificationType,

                    'type' =>
                        notificationType,

                    'actionType' =>
                        'OPEN_PROJECT_DETAILS',

                    'route' =>
                        'prospect_project_details',

                    // The actual approved Lead.
                    'leadId' =>
                        String.valueOf(approvedLead.Id),

                    // Original customer login Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    'recordId' =>
                        String.valueOf(approvedLead.Id),

                    'id' =>
                        notificationType + ':' +
                        String.valueOf(approvedLead.Id),

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

            if (projectNumber != null) {
                dataPayload.put(
                    'projectNumber',
                    String.valueOf(projectNumber)
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'PROJECT APPROVAL MULTI-LEAD PUSH: ' +
                'Lead=' + approvedLead.Id +
                ', Account=' + accountLeadId +
                ', Project=' + projectLabel +
                ', Devices=' + candidateTokens.size()
            );

            // =================================================
            // 9. SEND ONE PUSH PER UNIQUE DEVICE
            // =================================================

            for (String fcmToken : candidateTokens) {

                if (String.isBlank(fcmToken)) {
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
                        'PROJECT APPROVAL: Callout limit reached.'
                    );
                    break;
                }

                attempts++;

                try {

                    FirebasePushService.sendPushToToken(
                        fcmToken,
                        title,
                        body,
                        dataPayload
                    );

                    completed++;

                    System.debug(
                        LoggingLevel.INFO,
                        'PROJECT APPROVAL PUSH COMPLETED. ' +
                        'Lead=' + approvedLead.Id +
                        ', Project=' + projectLabel
                    );

                } catch (Exception ex) {

                    failed++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'PROJECT APPROVAL PUSH FAILED. ' +
                        'Lead=' + approvedLead.Id +
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
            '=== PROJECT APPROVAL MULTI-LEAD PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Approved Leads=' + approvedLeads.size() +
            ', Active Token Records=' + tokenRecordsFound +
            ', Attempts=' + attempts +
            ', Completed=' + completed +
            ', Failed=' + failed +
            ', Limit Reached=' + limitReached
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
                'PROJECT APPROVAL: Invalid account key. ' +
                'Lead=' + projectLead.Id
            );
        }

        return projectLead.Id;
    }
}