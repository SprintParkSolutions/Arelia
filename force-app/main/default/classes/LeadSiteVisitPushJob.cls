public without sharing class LeadSiteVisitPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> leadIds;

    public LeadSiteVisitPushJob(Set<Id> leadIds) {
        this.leadIds = leadIds == null
            ? new Set<Id>()
            : new Set<Id>(leadIds);
    }

    public void execute(QueueableContext context) {

        System.debug('====================================');
        System.debug('SITE VISIT APPOINTMENT PUSH STARTED');
        System.debug('LEAD IDS: ' + leadIds);
        System.debug('JOB ID: ' + context.getJobId());
        System.debug('====================================');

        if (leadIds.isEmpty()) {
            return;
        }

        // =====================================================
        // 1. LOAD APPOINTMENT LEADS
        // =====================================================

        List<Lead> leads = [
            SELECT
                Id,
                Name,
                IsConverted,
                Portal_Account_Key__c,
                Appointment_Date__c,
                Appointment_Time_Slots__c,
                Appointment_Confirmation_Type__c,
                Appointment_Status__c,
                Site_Location__c,
                Supervisor_User__c,
                Supervisor_User__r.Name
            FROM Lead
            WHERE Id IN :leadIds
        ];

        if (leads.isEmpty()) {
            return;
        }

        Set<Id> validLeadIds = new Set<Id>();

        Map<Id, Lead> leadMap =
            new Map<Id, Lead>();

        Map<Id, Id> accountByEventLead =
            new Map<Id, Id>();

        Set<Id> accountLeadIds =
            new Set<Id>();

        // =====================================================
        // 2. VALIDATE APPOINTMENTS AND FIND ACCOUNT LEAD
        // =====================================================

        for (Lead prospect : leads) {

            if (
                prospect.IsConverted == true ||
                prospect.Appointment_Date__c == null ||
                String.isBlank(
                    prospect.Appointment_Time_Slots__c
                )
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'SITE VISIT PUSH: Invalid appointment. Lead='
                    + prospect.Id
                );
                continue;
            }

            validLeadIds.add(prospect.Id);

            leadMap.put(
                prospect.Id,
                prospect
            );

            // Original Lead is the customer account identity.
            Id accountLeadId = prospect.Id;

            String accountKey =
                prospect.Portal_Account_Key__c;

            if (!String.isBlank(accountKey)) {

                try {

                    Id parsedKey =
                        (Id) accountKey.trim();

                    if (
                        parsedKey.getSObjectType() ==
                        Lead.SObjectType
                    ) {
                        accountLeadId = parsedKey;
                    }

                } catch (Exception ex) {

                    System.debug(
                        LoggingLevel.WARN,
                        'SITE VISIT PUSH: Invalid account key. Lead='
                        + prospect.Id
                    );
                }
            }

            accountByEventLead.put(
                prospect.Id,
                accountLeadId
            );

            accountLeadIds.add(
                accountLeadId
            );
        }

        if (validLeadIds.isEmpty()) {
            return;
        }

        // =====================================================
        // 3. FIND ALL PROJECT LEADS FOR THE CUSTOMER
        // =====================================================

        Set<String> accountKeyStrings =
            new Set<String>();

        for (Id accountId : accountLeadIds) {
            accountKeyStrings.add(
                String.valueOf(accountId)
            );
        }

        List<Lead> projectLeads = [
            SELECT
                Id,
                Name,
                CreatedDate,
                Portal_Account_Key__c
            FROM Lead
            WHERE Id IN :accountLeadIds
               OR Portal_Account_Key__c
                  IN :accountKeyStrings
            ORDER BY CreatedDate ASC, Id ASC
        ];

        Map<Id, Id> accountByProjectLead =
            new Map<Id, Id>();

        Map<Id, List<Id>> projectsByAccount =
            new Map<Id, List<Id>>();

        for (Id accountId : accountLeadIds) {

            projectsByAccount.put(
                accountId,
                new List<Id>()
            );
        }

        // =====================================================
        // 4. BUILD PROJECT GROUPS
        // =====================================================

        for (Lead projectLead : projectLeads) {

            Id accountId = projectLead.Id;

            if (
                !String.isBlank(
                    projectLead.Portal_Account_Key__c
                )
            ) {

                try {

                    Id parsedId = (Id)
                        projectLead.Portal_Account_Key__c.trim();

                    if (
                        parsedId.getSObjectType() ==
                        Lead.SObjectType
                    ) {
                        accountId = parsedId;
                    }

                } catch (Exception ex) {

                    System.debug(
                        LoggingLevel.WARN,
                        'SITE VISIT PUSH: Invalid project account key.'
                    );

                    continue;
                }
            }

            if (
                !projectsByAccount.containsKey(accountId)
            ) {
                continue;
            }

            accountByProjectLead.put(
                projectLead.Id,
                accountId
            );

            projectsByAccount
                .get(accountId)
                .add(projectLead.Id);
        }

        // =====================================================
        // 5. CALCULATE PROJECT LABELS
        // =====================================================

        Map<Id, String> projectLabelByLead =
            new Map<Id, String>();

        for (Id accountId : projectsByAccount.keySet()) {

            List<Id> accountProjects =
                projectsByAccount.get(accountId);

            Integer projectNumber = 0;

            for (Id projectLeadId : accountProjects) {

                projectNumber++;

                projectLabelByLead.put(
                    projectLeadId,
                    'Project ' + projectNumber
                );
            }
        }

        // =====================================================
        // 6. COLLECT ALL RELATED LEAD IDS FOR TOKENS
        // =====================================================

        Set<Id> tokenLeadIds =
            new Set<Id>();

        tokenLeadIds.addAll(accountLeadIds);

        for (Lead projectLead : projectLeads) {

            if (
                accountByProjectLead.containsKey(
                    projectLead.Id
                )
            ) {
                tokenLeadIds.add(
                    projectLead.Id
                );
            }
        }

        // =====================================================
        // 7. FETCH ACTIVE CUSTOMER DEVICE TOKENS
        // =====================================================

        List<Prospect_Device_Token__c> devices = [
            SELECT
                Id,
                Prospect_Lead__c,
                FCM_Token__c,
                Platform__c,
                Active__c,
                Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :tokenLeadIds
              AND Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST
        ];

        // One customer can have multiple devices.
        // Use a Set to prevent duplicate sends per event.

        Map<Id, Set<String>> tokensByAccount =
            new Map<Id, Set<String>>();

        for (Id accountId : accountLeadIds) {

            tokensByAccount.put(
                accountId,
                new Set<String>()
            );
        }

        for (Prospect_Device_Token__c device : devices) {

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

            // Allow a token registered on the original Lead.
            if (
                accountId == null &&
                accountLeadIds.contains(
                    device.Prospect_Lead__c
                )
            ) {
                accountId =
                    device.Prospect_Lead__c;
            }

            if (
                accountId == null ||
                !tokensByAccount.containsKey(accountId)
            ) {
                continue;
            }

            tokensByAccount
                .get(accountId)
                .add(device.FCM_Token__c.trim());
        }

        // =====================================================
        // 8. SEND PROJECT-SPECIFIC SITE VISIT NOTIFICATIONS
        // =====================================================

        Integer successCount = 0;
        Integer failureCount = 0;
        Integer skippedCount = 0;

        for (Id leadId : validLeadIds) {

            Lead prospect =
                leadMap.get(leadId);

            Id accountId =
                accountByEventLead.get(leadId);

            Set<String> deliveryTokens =
                tokensByAccount.get(accountId);

            if (
                deliveryTokens == null ||
                deliveryTokens.isEmpty()
            ) {

                skippedCount++;

                System.debug(
                    LoggingLevel.WARN,
                    'SITE VISIT PUSH: No active device token. ' +
                    'Lead=' + leadId +
                    ' Account=' + accountId
                );

                continue;
            }

            String projectLabel =
                projectLabelByLead.containsKey(leadId)
                ? projectLabelByLead.get(leadId)
                : 'Your Project';

            // =================================================
            // 9. BUILD NOTIFICATION TITLE AND BODY
            // =================================================

            String title =
                'Arelia - ' + projectLabel +
                ' - Site Visit Scheduled';

            String body =
                'Your site visit for ' +
                projectLabel +
                ' has been scheduled for ' +
                String.valueOf(
                    prospect.Appointment_Date__c
                ) +
                ' (' +
                prospect.Appointment_Time_Slots__c +
                '). Tap to review the details and confirm ' +
                'your availability.';

            String supervisorName = '';

            if (
                prospect.Supervisor_User__r != null
            ) {
                supervisorName =
                    prospect.Supervisor_User__r.Name;
            }

            String eventId =
                'SITE_VISIT_SCHEDULED:' +
                String.valueOf(prospect.Id) + ':' +
                String.valueOf(
                    prospect.Appointment_Date__c
                ) +
                ':' +
                prospect.Appointment_Time_Slots__c;

            // =================================================
            // 10. PROJECT-SPECIFIC FCM PAYLOAD
            // =================================================

            Map<String, String> payload =
                new Map<String, String>{

                    'id' => eventId,

                    'title' => title,

                    'body' => body,

                    'time' =>
                        Datetime.now().formatGMT(
                            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                        ),

                    'source' => 'Lead',

                    // Always use the Lead associated with
                    // this specific site visit appointment.
                    'recordId' =>
                        String.valueOf(prospect.Id),

                    'recipientType' => 'prospect',

                    'leadId' =>
                        String.valueOf(prospect.Id),

                    // Original customer account Lead.
                    'accountLeadId' =>
                        String.valueOf(accountId),

                    // Multi-project navigation support.
                    'projectLabel' => projectLabel,

                    'projectName' => projectLabel,

                    'notificationType' =>
                        'SITE_VISIT_SCHEDULED',

                    'actionType' =>
                        'OPEN_SITE_VISIT_APPROVAL',

                    'route' =>
                        'prospect_site_visit_approval',

                    'appointmentDate' =>
                        String.valueOf(
                            prospect.Appointment_Date__c
                        ),

                    'appointmentTimeSlot' =>
                        prospect.Appointment_Time_Slots__c,

                    'appointmentType' =>
                        prospect.Appointment_Confirmation_Type__c
                            == null
                            ? ''
                            : prospect
                                .Appointment_Confirmation_Type__c,

                    'appointmentStatus' =>
                        prospect.Appointment_Status__c
                            == null
                            ? ''
                            : prospect.Appointment_Status__c,

                    'siteLocation' =>
                        String.isBlank(
                            prospect.Site_Location__c
                        )
                            ? ''
                            : prospect.Site_Location__c,

                    'supervisorName' => supervisorName
                };

            System.debug(
                LoggingLevel.INFO,
                'SITE VISIT PUSH: ' +
                projectLabel +
                ' Lead=' + leadId +
                ' Account=' + accountId +
                ' DeviceCount=' + deliveryTokens.size()
            );

            // =================================================
            // 11. DELIVER TO ALL CUSTOMER DEVICES
            // =================================================

            for (String fcmToken : deliveryTokens) {

                // Keep HTTP callout headroom.
                if (
                    Limits.getCallouts() >=
                    Limits.getLimitCallouts() - 2
                ) {

                    System.debug(
                        LoggingLevel.ERROR,
                        'SITE VISIT PUSH: Callout limit approaching. ' +
                        'Remaining notifications not processed.'
                    );

                    return;
                }

                try {

                    FirebasePushService.sendPushToToken(
                        fcmToken,
                        title,
                        body,
                        payload
                    );

                    successCount++;

                    System.debug(
                        LoggingLevel.INFO,
                        'SITE VISIT PUSH ACCEPTED: ' +
                        projectLabel +
                        ' Lead=' + leadId
                    );

                } catch (Exception ex) {

                    failureCount++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'SITE VISIT PUSH FAILED: ' +
                        projectLabel +
                        ' Lead=' + leadId +
                        ' Error=' + ex.getMessage()
                    );
                }
            }
        }

        // =====================================================
        // 12. FINAL EXECUTION SUMMARY
        // =====================================================

        System.debug('====================================');
        System.debug('SITE VISIT APPOINTMENT PUSH FINISHED');
        System.debug('SUCCESSFUL FCM CALLS: ' + successCount);
        System.debug('FAILED FCM CALLS: ' + failureCount);
        System.debug('SKIPPED LEADS: ' + skippedCount);
        System.debug('====================================');
    }
}