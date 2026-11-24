public without sharing class ProspectPushNotificationQueueable
    implements Queueable, Database.AllowsCallouts {

    public static final String TYPE_SUPERVISOR_ASSIGNED =
        'SUPERVISOR_ASSIGNED';

    public static final String TYPE_SITE_VISIT_SCHEDULED =
        'SITE_VISIT_SCHEDULED';

    public static final String TYPE_PROJECT_DETAILS_REQUIRED =
        'PROJECT_DETAILS_REQUIRED';

    private static final Integer MAX_TOKENS_PER_JOB = 90;

    private Set<Id> leadIds;
    private String notificationType;

    public ProspectPushNotificationQueueable(
        Set<Id> leadIds,
        String notificationType
    ) {
        this.leadIds = leadIds == null
            ? new Set<Id>()
            : new Set<Id>(leadIds);

        this.notificationType = notificationType;
    }

    public void execute(QueueableContext context) {

        if (leadIds.isEmpty()) {
            return;
        }

        if (!isSupportedNotificationType()) {
            System.debug(
                LoggingLevel.ERROR,
                'Unsupported Prospect notification type: ' +
                notificationType
            );
            return;
        }

        // =====================================================
        // 1. GET EVENT LEADS
        // =====================================================

        List<Lead> eventLeads = [
            SELECT Id,
                   FirstName,
                   LastName,
                   Portal_Account_Key__c,
                   Project_Request_Submitted__c,
                   Supervisor_User__c,
                   Supervisor_User__r.Name,
                   Appointment_Date__c,
                   Appointment_Time_Slots__c,
                   Appointment_Status__c,
                   Appointment_Sent_date__c,
                   CreatedDate
            FROM Lead
            WHERE Id IN :leadIds
            WITH SYSTEM_MODE
        ];

        if (eventLeads.isEmpty()) {
            return;
        }

        // =====================================================
        // 2. RESOLVE ORIGINAL ACCOUNT LEAD
        // =====================================================

        Map<Id, Id> accountByEventLead =
            new Map<Id, Id>();

        Set<Id> accountLeadIds =
            new Set<Id>();

        Set<Id> tokenOwnerLeadIds =
            new Set<Id>();

        for (Lead eventLead : eventLeads) {

            Id accountLeadId =
                resolveAccountLeadId(eventLead);

            accountByEventLead.put(
                eventLead.Id,
                accountLeadId
            );

            accountLeadIds.add(accountLeadId);

            // Original Lead owns the customer's FCM token.
            tokenOwnerLeadIds.add(accountLeadId);

            // Support independently registered project Leads.
            tokenOwnerLeadIds.add(eventLead.Id);
        }

        // =====================================================
        // 3. IDENTIFY PROJECT NUMBERS
        // =====================================================

        Set<String> accountKeys =
            new Set<String>();

        for (Id accountId : accountLeadIds) {
            accountKeys.add(
                String.valueOf(accountId)
            );
        }

        List<Lead> accountProjects = [
            SELECT Id,
                   Portal_Account_Key__c,
                   CreatedDate
            FROM Lead
            WHERE Id IN :accountLeadIds
               OR Portal_Account_Key__c IN :accountKeys
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ];

        Map<Id, Integer> projectNumberByLead =
            new Map<Id, Integer>();

        Map<Id, Integer> nextNumberByAccount =
            new Map<Id, Integer>();

        for (Lead projectLead : accountProjects) {

            Id accountId =
                resolveAccountLeadId(projectLead);

            if (!accountLeadIds.contains(accountId)) {
                continue;
            }

            Integer projectNumber =
                nextNumberByAccount.containsKey(accountId)
                    ? nextNumberByAccount.get(accountId) + 1
                    : 1;

            nextNumberByAccount.put(
                accountId,
                projectNumber
            );

            projectNumberByLead.put(
                projectLead.Id,
                projectNumber
            );
        }

        // =====================================================
        // 4. FETCH ACCOUNT-WIDE DEVICE TOKENS
        // =====================================================

        List<Prospect_Device_Token__c> tokenRecords = [
            SELECT Id,
                   Prospect_Lead__c,
                   Device_Id__c,
                   FCM_Token__c,
                   Platform__c,
                   Active__c,
                   Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :tokenOwnerLeadIds
              AND Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Last_Seen__c DESC
            NULLS LAST
        ];

        if (tokenRecords.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No account-wide Prospect device tokens found.'
            );
            return;
        }

        Map<Id, List<Prospect_Device_Token__c>>
            tokensByOwner =
                new Map<
                    Id,
                    List<Prospect_Device_Token__c>
                >();

        for (Prospect_Device_Token__c tokenRecord :
             tokenRecords) {

            if (
                tokenRecord.Prospect_Lead__c == null ||
                String.isBlank(tokenRecord.FCM_Token__c)
            ) {
                continue;
            }

            Id ownerId =
                tokenRecord.Prospect_Lead__c;

            if (!tokensByOwner.containsKey(ownerId)) {
                tokensByOwner.put(
                    ownerId,
                    new List<Prospect_Device_Token__c>()
                );
            }

            tokensByOwner.get(ownerId).add(
                tokenRecord
            );
        }

        // =====================================================
        // 5. SEND PROJECT-SPECIFIC NOTIFICATIONS
        // =====================================================

        List<Prospect_Device_Token__c>
            tokensToDeactivate =
                new List<Prospect_Device_Token__c>();

        Set<Id> invalidTokenIds =
            new Set<Id>();

        Integer processedTokenCount = 0;
        Integer successfulNotificationCount = 0;
        Integer failedNotificationCount = 0;

        Boolean limitReached = false;

        for (Lead eventLead : eventLeads) {

            // Preserve Project Details reminder condition.
            if (
                notificationType ==
                    TYPE_PROJECT_DETAILS_REQUIRED &&
                eventLead.Project_Request_Submitted__c == true
            ) {
                continue;
            }

            Id accountLeadId =
                accountByEventLead.get(
                    eventLead.Id
                );

            Integer projectNumber =
                projectNumberByLead.get(
                    eventLead.Id
                );

            List<Prospect_Device_Token__c>
                candidateTokens =
                    new List<Prospect_Device_Token__c>();

            if (
                tokensByOwner.containsKey(accountLeadId)
            ) {
                candidateTokens.addAll(
                    tokensByOwner.get(accountLeadId)
                );
            }

            if (
                eventLead.Id != accountLeadId &&
                tokensByOwner.containsKey(eventLead.Id)
            ) {
                candidateTokens.addAll(
                    tokensByOwner.get(eventLead.Id)
                );
            }

            Set<String> sentDeviceTokens =
                new Set<String>();

            for (
                Prospect_Device_Token__c tokenRecord :
                candidateTokens
            ) {

                String fcmToken =
                    tokenRecord.FCM_Token__c.trim();

                if (
                    sentDeviceTokens.contains(fcmToken)
                ) {
                    continue;
                }

                if (
                    processedTokenCount >= MAX_TOKENS_PER_JOB ||
                    Limits.getCallouts() >=
                        Limits.getLimitCallouts() - 2
                ) {
                    limitReached = true;
                    break;
                }

                sentDeviceTokens.add(fcmToken);

                processedTokenCount++;

                SendResult result =
                    sendNotification(
                        tokenRecord,
                        eventLead,
                        projectNumber
                    );

                if (result.success) {
                    successfulNotificationCount++;
                } else {
                    failedNotificationCount++;
                }

                if (
                    result.deactivateToken &&
                    !invalidTokenIds.contains(
                        tokenRecord.Id
                    )
                ) {

                    invalidTokenIds.add(
                        tokenRecord.Id
                    );

                    tokenRecord.Active__c = false;

                    tokensToDeactivate.add(
                        tokenRecord
                    );
                }
            }

            System.debug(
                LoggingLevel.INFO,
                'PROSPECT MULTI-PROJECT PUSH: ' +
                'type=' + notificationType +
                ', eventLead=' + eventLead.Id +
                ', accountLead=' + accountLeadId +
                ', projectNumber=' + projectNumber
            );

            if (limitReached) {
                System.debug(
                    LoggingLevel.WARN,
                    'Prospect push limit reached. ' +
                    'Some notifications were not processed.'
                );
                break;
            }
        }

        // =====================================================
        // 6. DEACTIVATE INVALID TOKENS
        // =====================================================

        if (!tokensToDeactivate.isEmpty()) {

            try {
                update as system tokensToDeactivate;
            } catch (DmlException ex) {

                System.debug(
                    LoggingLevel.ERROR,
                    'Unable to deactivate Firebase tokens: ' +
                    ex.getMessage()
                );
            }
        }

        System.debug(
            LoggingLevel.INFO,
            'PROSPECT PUSH COMPLETE. Processed=' +
            processedTokenCount +
            ', successful=' +
            successfulNotificationCount +
            ', failed=' +
            failedNotificationCount
        );
    }

    // =========================================================
    // 7. RESOLVE ORIGINAL ACCOUNT LEAD
    // =========================================================

    private static Id resolveAccountLeadId(
        Lead eventLead
    ) {

        if (
            String.isBlank(
                eventLead.Portal_Account_Key__c
            )
        ) {
            return eventLead.Id;
        }

        try {

            Id accountLeadId =
                (Id) eventLead.Portal_Account_Key__c.trim();

            if (
                accountLeadId.getSObjectType() ==
                    Lead.SObjectType
            ) {
                return accountLeadId;
            }

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.WARN,
                'Invalid Portal Account Key for Lead: ' +
                eventLead.Id
            );
        }

        return eventLead.Id;
    }

    // =========================================================
    // 8. SEND FIREBASE NOTIFICATION
    // =========================================================

    private SendResult sendNotification(
        Prospect_Device_Token__c tokenRecord,
        Lead leadRecord,
        Integer projectNumber
    ) {

        SendResult result = new SendResult();

        try {

            String originalTitle =
                getNotificationTitle();

            String title = originalTitle;

            // Include Project 1, Project 2, Project 3, etc.
            if (projectNumber != null) {

                title =
                    'Arelia - Project ' +
                    String.valueOf(projectNumber) +
                    ': ' +
                    originalTitle;
            }

            String body =
                getNotificationBody(leadRecord);

            Map<String, String> dataPayload =
                buildDataPayload(
                    leadRecord,
                    title,
                    body,
                    projectNumber
                );

            FirebasePushService.sendPushToToken(
                tokenRecord.FCM_Token__c,
                title,
                body,
                dataPayload
            );

            result.success = true;
            result.deactivateToken = false;

            System.debug(
                LoggingLevel.INFO,
                'Prospect notification sent successfully. ' +
                'Lead=' + leadRecord.Id +
                ', Project=' + projectNumber +
                ', Type=' + notificationType
            );

        } catch (Exception ex) {

            result.success = false;

            String errorMessage =
                ex.getMessage();

            result.deactivateToken =
                isInvalidFirebaseToken(
                    errorMessage
                );

            System.debug(
                LoggingLevel.ERROR,
                'Prospect Firebase notification failed. ' +
                'Lead=' + leadRecord.Id +
                ', Type=' + notificationType +
                ', Error=' + errorMessage
            );
        }

        return result;
    }

    // =========================================================
    // 9. BUILD FLUTTER NOTIFICATION PAYLOAD
    // =========================================================

    private Map<String, String> buildDataPayload(
        Lead leadRecord,
        String title,
        String body,
        Integer projectNumber
    ) {

        Map<String, String> payload =
            new Map<String, String>{

                'id' =>
                    getEventId(leadRecord),

                'title' => title,

                'body' => body,

                'time' =>
                    Datetime.now().formatGMT(
                        'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                    ),

                'source' => 'Lead',

                'recordId' =>
                    String.valueOf(leadRecord.Id),

                'recipientType' => 'prospect',

                'leadId' =>
                    String.valueOf(leadRecord.Id),

                'notificationType' =>
                    notificationType,

                'actionType' =>
                    getActionType(),

                'route' =>
                    getRoute()
            };

        if (projectNumber != null) {

            payload.put(
                'projectNumber',
                String.valueOf(projectNumber)
            );

            payload.put(
                'projectLabel',
                'Project ' +
                    String.valueOf(projectNumber)
            );
        }

        return payload;
    }

    // =========================================================
    // 10. GENERATE EVENT ID
    // =========================================================

    private String getEventId(
        Lead leadRecord
    ) {

        if (
            notificationType ==
                TYPE_PROJECT_DETAILS_REQUIRED
        ) {
            return
                TYPE_PROJECT_DETAILS_REQUIRED +
                ':' +
                String.valueOf(leadRecord.Id);
        }

        if (
            notificationType ==
                TYPE_SUPERVISOR_ASSIGNED
        ) {
            return
                TYPE_SUPERVISOR_ASSIGNED +
                ':' +
                String.valueOf(leadRecord.Id) +
                ':' +
                String.valueOf(
                    leadRecord.Supervisor_User__c
                );
        }

        return
            TYPE_SITE_VISIT_SCHEDULED +
            ':' +
            String.valueOf(leadRecord.Id) +
            ':' +
            String.valueOf(
                leadRecord.Appointment_Date__c
            ) +
            ':' +
            String.valueOf(
                leadRecord.Appointment_Time_Slots__c
            );
    }

    // =========================================================
    // 11. GET ACTION TYPE
    // =========================================================

    private String getActionType() {

        if (
            notificationType ==
                TYPE_PROJECT_DETAILS_REQUIRED
        ) {
            return 'OPEN_PROJECT_DETAILS';
        }

        if (
            notificationType ==
                TYPE_SUPERVISOR_ASSIGNED
        ) {
            return 'OPEN_SUPERVISOR_DETAILS';
        }

        return 'OPEN_SITE_VISIT_APPROVAL';
    }

    // =========================================================
    // 12. GET FLUTTER ROUTE
    // =========================================================

    private String getRoute() {

        if (
            notificationType ==
                TYPE_PROJECT_DETAILS_REQUIRED
        ) {
            return 'prospect_project_details';
        }

        if (
            notificationType ==
                TYPE_SUPERVISOR_ASSIGNED
        ) {
            return 'prospect_supervisor_details';
        }

        return 'prospect_site_visit_approval';
    }

    // =========================================================
    // 13. GET NOTIFICATION TITLE
    // =========================================================

    private String getNotificationTitle() {

        if (
            notificationType ==
                TYPE_PROJECT_DETAILS_REQUIRED
        ) {
            return 'Complete Your Project Details';
        }

        if (
            notificationType ==
                TYPE_SUPERVISOR_ASSIGNED
        ) {
            return 'Supervisor Assigned';
        }

        return 'Site Visit Scheduled';
    }

    // =========================================================
    // 14. GET NOTIFICATION BODY
    // =========================================================

    private String getNotificationBody(
        Lead leadRecord
    ) {

        if (
            notificationType ==
                TYPE_PROJECT_DETAILS_REQUIRED
        ) {

            if (
                String.isNotBlank(
                    leadRecord.FirstName
                )
            ) {
                return
                    'Hi ' +
                    leadRecord.FirstName +
                    ', please complete your project details ' +
                    'so our Arelia team can better understand ' +
                    'your requirements and plan the next steps ' +
                    'for your project.';
            }

            return
                'Please complete your project details so our ' +
                'Arelia team can better understand your ' +
                'requirements and plan the next steps for ' +
                'your project.';
        }

        if (
            notificationType ==
                TYPE_SUPERVISOR_ASSIGNED
        ) {

            String supervisorName;

            if (
                leadRecord.Supervisor_User__c != null &&
                leadRecord.Supervisor_User__r != null
            ) {
                supervisorName =
                    leadRecord.Supervisor_User__r.Name;
            }

            if (
                String.isNotBlank(supervisorName)
            ) {
                return
                    supervisorName +
                    ' has been assigned as your project supervisor.';
            }

            return
                'A supervisor has been assigned to your project.';
        }

        String appointmentDate =
            leadRecord.Appointment_Date__c == null
                ? null
                : String.valueOf(
                    leadRecord.Appointment_Date__c
                );

        String appointmentTimeSlot =
            leadRecord.Appointment_Time_Slots__c;

        if (
            String.isNotBlank(appointmentDate) &&
            String.isNotBlank(appointmentTimeSlot)
        ) {
            return
                'Your site visit is scheduled for ' +
                appointmentDate +
                ' during ' +
                appointmentTimeSlot +
                '. Please review and confirm it.';
        }

        return
            'Your supervisor scheduled a site visit. ' +
            'Please review and confirm it.';
    }

    // =========================================================
    // 15. INVALID FIREBASE TOKEN HANDLING
    // =========================================================

    private Boolean isInvalidFirebaseToken(
        String errorMessage
    ) {

        if (String.isBlank(errorMessage)) {
            return false;
        }

        String normalizedError =
            errorMessage.toUpperCase();

        return
            normalizedError.contains('UNREGISTERED') ||
            normalizedError.contains(
                'REGISTRATION-TOKEN-NOT-REGISTERED'
            ) ||
            normalizedError.contains(
                'INVALID REGISTRATION TOKEN'
            );
    }

    // =========================================================
    // 16. SUPPORTED NOTIFICATION TYPES
    // =========================================================

    private Boolean isSupportedNotificationType() {

        return
            notificationType ==
                TYPE_SUPERVISOR_ASSIGNED ||
            notificationType ==
                TYPE_SITE_VISIT_SCHEDULED ||
            notificationType ==
                TYPE_PROJECT_DETAILS_REQUIRED;
    }

    private class SendResult {

        public Boolean success;
        public Boolean deactivateToken;

        public SendResult() {
            success = false;
            deactivateToken = false;
        }
    }
}