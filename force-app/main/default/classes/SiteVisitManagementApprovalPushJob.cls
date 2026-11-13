public without sharing class SiteVisitManagementApprovalPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> reportIds;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    private static final String NOTIFICATION_TYPE =
        'SITE_VISIT_REPORT_APPROVED';

    public SiteVisitManagementApprovalPushJob(
        Set<Id> reportIds
    ) {
        this.reportIds = reportIds == null
            ? new Set<Id>()
            : new Set<Id>(reportIds);
    }

    public void execute(QueueableContext context) {

        if (reportIds.isEmpty()) {
            return;
        }

        // =====================================================
        // 1. GET ELIGIBLE SITE VISIT REPORTS
        // =====================================================

        List<Site_Visit_Report__c> reports = [
            SELECT
                Id,
                Lead__c,
                Management_Approval__c,
                Is_Final_Submitted__c
            FROM Site_Visit_Report__c
            WHERE Id IN :reportIds
              AND Lead__c != null
              AND Management_Approval__c = true
              AND Is_Final_Submitted__c = true
            WITH SYSTEM_MODE
        ];

        if (reports.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SITE VISIT APPROVAL: No eligible reports.'
            );
            return;
        }

        // =====================================================
        // 2. GET ACTUAL PROJECT LEADS
        // =====================================================

        Set<Id> eventLeadIds = new Set<Id>();

        for (Site_Visit_Report__c report : reports) {
            eventLeadIds.add(report.Lead__c);
        }

        List<Lead> eventLeads = [
            SELECT
                Id,
                Portal_Account_Key__c,
                CreatedDate
            FROM Lead
            WHERE Id IN :eventLeadIds
            WITH SYSTEM_MODE
        ];

        Map<Id, Id> accountByEventLead =
            new Map<Id, Id>();

        Set<Id> originalAccountLeadIds =
            new Set<Id>();

        for (Lead eventLead : eventLeads) {

            Id accountLeadId =
                resolveOriginalLeadId(eventLead);

            accountByEventLead.put(
                eventLead.Id,
                accountLeadId
            );

            originalAccountLeadIds.add(
                accountLeadId
            );
        }

        if (originalAccountLeadIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SITE VISIT APPROVAL: No account Leads.'
            );
            return;
        }

        // =====================================================
        // 3. GET ALL LEADS BELONGING TO EACH CUSTOMER
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
                CreatedDate
            FROM Lead
            WHERE Id IN :originalAccountLeadIds
               OR Portal_Account_Key__c IN :accountKeys
            WITH SYSTEM_MODE
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
        // 5. COLLECT ALL PROJECT LEAD IDS
        // =====================================================

        Set<Id> allProjectLeadIds =
            new Set<Id>();

        for (Id accountLeadId : leadIdsByAccount.keySet()) {
            allProjectLeadIds.addAll(
                leadIdsByAccount.get(accountLeadId)
            );
        }

        // =====================================================
        // 6. FETCH ACTIVE ACCOUNT-WIDE FCM TOKENS
        // =====================================================

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
            WITH SYSTEM_MODE
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

            // Set prevents duplicate device notifications.
            tokensByAccount.get(accountLeadId).add(
                fcmToken
            );

            tokenRecordsFound++;
        }

        // =====================================================
        // 7. SEND PROJECT-SPECIFIC REPORT APPROVAL PUSH
        // =====================================================

        Integer attempts = 0;
        Integer completed = 0;
        Integer failed = 0;

        Boolean limitReached = false;

        for (Site_Visit_Report__c report : reports) {

            Id accountLeadId =
                accountByEventLead.get(
                    report.Lead__c
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
                    'SITE VISIT APPROVAL: No active account token. ' +
                    'Report=' + report.Id +
                    ', Lead=' + report.Lead__c +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            Integer projectNumber =
                projectNumberByLead.get(
                    report.Lead__c
                );

            String projectLabel =
                projectNumber == null
                    ? 'Your Project'
                    : 'Project ' +
                        String.valueOf(projectNumber);

            // Preserve existing notification message.
            String title =
                'Arelia - ' + projectLabel +
                ': Site Visit Report Approved';

            String body =
                'Your site visit report has been approved. ' +
                'Tap to view the details.';

            // =================================================
            // 8. BUILD FLUTTER NOTIFICATION PAYLOAD
            // =================================================

            Map<String, String> payload =
                new Map<String, String>{

                    'id' =>
                        NOTIFICATION_TYPE + ':' +
                        String.valueOf(report.Id),

                    'title' => title,

                    'body' => body,

                    'time' =>
                        Datetime.now().formatGMT(
                            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                        ),

                    'source' =>
                        'Site_Visit_Report__c',

                    'recordId' =>
                        String.valueOf(report.Id),

                    'recipientType' =>
                        'prospect',

                    'notificationType' =>
                        NOTIFICATION_TYPE,

                    'type' =>
                        NOTIFICATION_TYPE,

                    'actionType' =>
                        'OPEN_SITE_VISIT_REPORT',

                    'route' =>
                        'prospect_site_visit_report',

                    // Actual project Lead.
                    'leadId' =>
                        String.valueOf(report.Lead__c),

                    // Original customer login Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    // Actual Site Visit Report.
                    'reportId' =>
                        String.valueOf(report.Id),

                    'projectLabel' =>
                        projectLabel
                };

            if (projectNumber != null) {
                payload.put(
                    'projectNumber',
                    String.valueOf(projectNumber)
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'SITE VISIT REPORT MULTI-PROJECT PUSH: ' +
                'Report=' + report.Id +
                ', Lead=' + report.Lead__c +
                ', Account=' + accountLeadId +
                ', Project=' + projectLabel +
                ', Devices=' + candidateTokens.size()
            );

            // =================================================
            // 9. SEND TO EACH UNIQUE CUSTOMER DEVICE
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
                        'SITE VISIT APPROVAL: Callout limit reached.'
                    );

                    break;
                }

                attempts++;

                try {

                    FirebasePushService.sendPushToToken(
                        fcmToken,
                        title,
                        body,
                        payload
                    );

                    completed++;

                    System.debug(
                        LoggingLevel.INFO,
                        'SITE VISIT APPROVAL PUSH COMPLETED. ' +
                        'Report=' + report.Id +
                        ', Lead=' + report.Lead__c +
                        ', Project=' + projectLabel
                    );

                } catch (Exception ex) {

                    failed++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'SITE VISIT APPROVAL PUSH FAILED. ' +
                        'Report=' + report.Id +
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
            '=== SITE VISIT REPORT MULTI-PROJECT PUSH SUMMARY ==='
        );

        System.debug(
            LoggingLevel.INFO,
            'Reports=' + reports.size() +
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
                'SITE VISIT APPROVAL: Invalid account key. ' +
                'Lead=' + projectLead.Id
            );
        }

        return projectLead.Id;
    }
}