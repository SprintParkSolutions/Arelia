public with sharing class AreliaPushNotificationService {

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    // =========================================================
    // 1. EXISTING PUBLIC METHOD - UNCHANGED
    // =========================================================

    public static void sendToContactAsync(
        Id contactId,
        String title,
        String messageBody,
        String notificationType,
        String recordId
    ) {
        System.enqueueJob(
            new SendPushJob(
                contactId,
                title,
                messageBody,
                notificationType,
                recordId
            )
        );
    }

    // Document upload overload: keep recordId as ContentDocumentId,
    // while passing the owning Project__c ID independently.
    public static void sendToContactAsync(
        Id contactId,
        String title,
        String messageBody,
        String notificationType,
        String recordId,
        Id projectId
    ) {
        System.enqueueJob(
            new SendPushJob(
                contactId,
                title,
                messageBody,
                notificationType,
                recordId,
                projectId
            )
        );
    }

    // =========================================================
    // 2. QUEUEABLE NOTIFICATION JOB
    // =========================================================

    public class SendPushJob
        implements Queueable, Database.AllowsCallouts {

        private Id contactId;
        private String title;
        private String messageBody;
        private String notificationType;
        private String recordId;
        private Id suppliedProjectId;

        public SendPushJob(
            Id contactId,
            String title,
            String messageBody,
            String notificationType,
            String recordId
        ) {
            this.contactId = contactId;
            this.title = title;
            this.messageBody = messageBody;
            this.notificationType = notificationType;
            this.recordId = recordId;
        }

        // Overload for document uploads. Other existing callers
        // continue using the original five-argument constructor.
        public SendPushJob(
            Id contactId,
            String title,
            String messageBody,
            String notificationType,
            String recordId,
            Id projectId
        ) {
            this(contactId, title, messageBody, notificationType, recordId);
            this.suppliedProjectId = projectId;
        }

        public void execute(QueueableContext context) {

            if (contactId == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROJECT PUSH: Contact ID is null.'
                );
                return;
            }

            String safeTitle = getSafeText(
                title,
                'Arelia Update'
            );

            String safeBody = getSafeText(
                messageBody,
                'You have a new update.'
            );

            String safeType = getSafeText(
                notificationType,
                'GENERAL'
            );

            String safeRecordId =
                String.isBlank(recordId)
                    ? ''
                    : recordId;

            Id projectId = suppliedProjectId;
            Id opportunityId;
            Id eventLeadId;
            Id accountLeadId;

            String projectName;
            String projectLabel;

            // =================================================
            // 3. VALIDATE PROJECT ID
            // =================================================

            if (
                projectId == null &&
                !String.isBlank(safeRecordId)
            ) {

                try {
                    Id parsedId = (Id) safeRecordId;

                    if (
                        parsedId.getSObjectType() ==
                        Project__c.SObjectType
                    ) {
                        projectId = parsedId;
                    }

                } catch (Exception ex) {

                    System.debug(
                        LoggingLevel.WARN,
                        'PROJECT PUSH: Invalid Project ID.'
                    );
                }
            }

            // =================================================
            // 4. GET ACTUAL PROJECT AND OPPORTUNITY
            // =================================================

            if (projectId != null) {

                List<Project__c> projects = [
                    SELECT
                        Id,
                        Name,
                        Client__c,
                        Project_Name__c
                    FROM Project__c
                    WHERE Id = :projectId
                      AND Client__c = :contactId
                    LIMIT 1
                ];

                if (projects.isEmpty()) {

                    System.debug(
                        LoggingLevel.WARN,
                        'PROJECT PUSH: Project not linked ' +
                        'to supplied Contact.'
                    );

                    return;
                }

                Project__c projectRecord = projects[0];

                projectName = projectRecord.Name;

                // Actual Opportunity linked to this Project.
                opportunityId =
                    projectRecord.Project_Name__c;
            }

            // =================================================
            // 5. FIND THE CONVERTED LEAD OF THIS PROJECT
            // =================================================

            Lead eventLead;

            if (opportunityId != null) {

                List<Lead> matchingLeads = [
                    SELECT
                        Id,
                        IsConverted,
                        ConvertedOpportunityId,
                        ConvertedContactId,
                        Portal_Account_Key__c,
                        CreatedDate
                    FROM Lead
                    WHERE IsConverted = true
                      AND ConvertedOpportunityId =
                          :opportunityId
                    ORDER BY CreatedDate ASC, Id ASC
                    LIMIT 1
                ];

                if (!matchingLeads.isEmpty()) {
                    eventLead = matchingLeads[0];
                }
            }

            // =================================================
            // 6. RESOLVE ORIGINAL ACCOUNT LEAD
            // =================================================

            if (eventLead != null) {

                eventLeadId = eventLead.Id;

                accountLeadId =
                    resolveOriginalLeadId(eventLead);
            }

            // =================================================
            // 7. IDENTIFY PROJECT NUMBER
            // =================================================

            Set<Id> relatedLeadIds =
                new Set<Id>();

            Set<Id> relatedContactIds =
                new Set<Id>();

            if (accountLeadId != null) {

                String accountKey =
                    String.valueOf(accountLeadId);

                List<Lead> accountProjects = [
                    SELECT
                        Id,
                        Portal_Account_Key__c,
                        ConvertedContactId,
                        CreatedDate
                    FROM Lead
                    WHERE Id = :accountLeadId
                       OR Portal_Account_Key__c =
                           :accountKey
                    ORDER BY CreatedDate ASC, Id ASC
                ];

                Integer projectNumber = 0;

                for (Lead projectLead : accountProjects) {

                    if (
                        resolveOriginalLeadId(projectLead) !=
                        accountLeadId
                    ) {
                        continue;
                    }

                    relatedLeadIds.add(projectLead.Id);

                    if (
                        projectLead.ConvertedContactId != null
                    ) {
                        relatedContactIds.add(
                            projectLead.ConvertedContactId
                        );
                    }

                    projectNumber++;

                    if (projectLead.Id == eventLeadId) {

                        projectLabel =
                            'Project ' +
                            String.valueOf(projectNumber);
                    }
                }
            }

            // Use actual Salesforce project name only when
            // no numbered Lead/project match is available.
            if (
                String.isBlank(projectLabel) &&
                !String.isBlank(projectName)
            ) {
                projectLabel = projectName;
            }

            // =================================================
            // 8. CREATE PROJECT-SPECIFIC TITLE
            // =================================================

            if (!String.isBlank(projectLabel)) {

                safeTitle =
                    'Arelia - ' +
                    projectLabel +
                    ': ' +
                    safeTitle;
            }

            // =================================================
            // 9. COLLECT ACTIVE DEVICE TOKENS
            // =================================================

            Set<String> deliveryTokens =
                new Set<String>();

            // Preserve existing Contact-based delivery.
            for (Mobile_Device_Token__c device : [
                SELECT
                    Id,
                    Contact__c,
                    FCM_Token__c,
                    Active__c,
                    Last_Seen__c
                FROM Mobile_Device_Token__c
                WHERE Contact__c = :contactId
                  AND Active__c = true
                ORDER BY Last_Seen__c DESC
                NULLS LAST
            ]) {

                if (
                    !String.isBlank(device.FCM_Token__c)
                ) {
                    deliveryTokens.add(
                        device.FCM_Token__c.trim()
                    );
                }
            }

            // =================================================
            // 10. COLLECT TOKENS FROM ALL RELATED LEADS
            // =================================================

            if (!relatedLeadIds.isEmpty()) {

                for (Prospect_Device_Token__c device : [
                    SELECT
                        Id,
                        Prospect_Lead__c,
                        FCM_Token__c,
                        Active__c
                    FROM Prospect_Device_Token__c
                    WHERE Prospect_Lead__c
                        IN :relatedLeadIds
                      AND Active__c = true
                ]) {

                    if (
                        !String.isBlank(device.FCM_Token__c)
                    ) {
                        deliveryTokens.add(
                            device.FCM_Token__c.trim()
                        );
                    }
                }
            }

            // =================================================
            // 11. COLLECT RELATED CONVERTED CONTACT TOKENS
            // =================================================

            if (!relatedContactIds.isEmpty()) {

                for (Mobile_Device_Token__c device : [
                    SELECT
                        Id,
                        Contact__c,
                        FCM_Token__c,
                        Active__c
                    FROM Mobile_Device_Token__c
                    WHERE Contact__c
                        IN :relatedContactIds
                      AND Active__c = true
                ]) {

                    if (
                        !String.isBlank(device.FCM_Token__c)
                    ) {
                        deliveryTokens.add(
                            device.FCM_Token__c.trim()
                        );
                    }
                }
            }

            // =================================================
            // 12. BUILD FLUTTER NOTIFICATION PAYLOAD
            // =================================================

            Map<String, String> dataPayload =
                new Map<String, String>{

                    'type' => safeType,

                    'notificationType' => safeType,

                    'recordId' => safeRecordId,

                    'contactId' =>
                        String.valueOf(contactId),

                    'id' =>
                        safeType + ':' + safeRecordId,

                    'title' => safeTitle,

                    'body' => safeBody,

                    'time' =>
                        Datetime.now().formatGMT(
                            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                        ),

                    'source' => 'Project',

                    'recipientType' => 'prospect'
                };

            // Keep ContentDocumentId available for document navigation.
            // Do not replace the existing recordId with Project__c.Id.
            if (
                safeType == 'file_upload' &&
                !String.isBlank(safeRecordId)
            ) {
                dataPayload.put('documentId', safeRecordId);
            }

            if (projectId != null) {

                dataPayload.put(
                    'projectId',
                    String.valueOf(projectId)
                );
            }

            if (opportunityId != null) {

                dataPayload.put(
                    'opportunityId',
                    String.valueOf(opportunityId)
                );
            }

            if (eventLeadId != null) {

                dataPayload.put(
                    'leadId',
                    String.valueOf(eventLeadId)
                );
            }

            if (accountLeadId != null) {

                dataPayload.put(
                    'accountLeadId',
                    String.valueOf(accountLeadId)
                );
            }

            if (!String.isBlank(projectLabel)) {

                dataPayload.put(
                    'projectLabel',
                    projectLabel
                );

                if (
                    projectLabel.startsWith('Project ')
                ) {
                    dataPayload.put(
                        'projectNumber',
                        projectLabel.substring(8)
                    );
                }
            }

            // =================================================
            // 13. SEND PUSH TO UNIQUE CUSTOMER DEVICES
            // =================================================

            Integer attempts = 0;
            Integer completed = 0;
            Integer failed = 0;

            if (deliveryTokens.isEmpty()) {

                System.debug(
                    LoggingLevel.WARN,
                    'PROJECT PUSH: No active device tokens. ' +
                    'Contact=' + contactId +
                    ', Project=' + safeRecordId
                );

            } else {

                for (String fcmToken : deliveryTokens) {

                    if (
                        attempts >= MAX_PUSH_ATTEMPTS ||
                        Limits.getCallouts() >=
                            Limits.getLimitCallouts() - 2
                    ) {

                        System.debug(
                            LoggingLevel.WARN,
                            'PROJECT PUSH: Callout safety limit reached.'
                        );

                        break;
                    }

                    attempts++;

                    try {

                        FirebasePushService.sendPushToToken(
                            fcmToken,
                            safeTitle,
                            safeBody,
                            dataPayload
                        );

                        completed++;

                        System.debug(
                            LoggingLevel.INFO,
                            'PROJECT MULTI-LEAD PUSH COMPLETED. ' +
                            'Project=' + safeRecordId +
                            ', Lead=' + eventLeadId +
                            ', Account=' + accountLeadId
                        );

                    } catch (Exception ex) {

                        failed++;

                        System.debug(
                            LoggingLevel.ERROR,
                            'PROJECT PUSH FAILED. ' +
                            'Project=' + safeRecordId +
                            ', Error=' + ex.getMessage()
                        );
                    }
                }
            }

            // =================================================
            // 14. PRESERVE EXISTING NOTIFICATION HISTORY
            // =================================================

            // Save only after Firebase callouts finish.
            Id historyId = saveNotificationHistory(
                contactId,
                safeTitle,
                safeBody,
                safeType,
                safeRecordId
            );

            System.debug(
                LoggingLevel.INFO,
                'PROJECT PUSH SUMMARY: ' +
                'Project=' + safeRecordId +
                ', Label=' + projectLabel +
                ', Lead=' + eventLeadId +
                ', Account=' + accountLeadId +
                ', Devices=' + deliveryTokens.size() +
                ', Attempts=' + attempts +
                ', Completed=' + completed +
                ', Failed=' + failed +
                ', History=' + historyId
            );
        }
    }

    // =========================================================
    // 15. RESOLVE ORIGINAL ACCOUNT LEAD
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
                'PROJECT PUSH: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }

    // =========================================================
    // 16. TEXT HELPER
    // =========================================================

    private static String getSafeText(
        String value,
        String defaultValue
    ) {
        return String.isBlank(value)
            ? defaultValue
            : value;
    }

    // =========================================================
    // 17. PRESERVE EXISTING HISTORY SAVE
    // =========================================================

    private static Id saveNotificationHistory(
        Id contactId,
        String title,
        String messageBody,
        String notificationType,
        String recordId
    ) {

        if (contactId == null) {
            return null;
        }

        try {

            Mobile_Notification__c notificationRec =
                new Mobile_Notification__c();

            notificationRec.Contact__c = contactId;
            notificationRec.Title__c = title;
            notificationRec.Message__c = messageBody;
            notificationRec.Notification_Type__c =
                notificationType;
            notificationRec.Related_Record_Id__c =
                recordId;
            notificationRec.Read__c = false;
            notificationRec.Sent_On__c = System.now();

            Database.SaveResult saveResult =
                Database.insert(
                    notificationRec,
                    false
                );

            if (saveResult.isSuccess()) {
                return saveResult.getId();
            }

            if (!saveResult.getErrors().isEmpty()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'PROJECT PUSH: History save failed. ' +
                    saveResult.getErrors()[0].getMessage()
                );
            }

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.ERROR,
                'PROJECT PUSH: History exception: ' +
                ex.getMessage()
            );
        }

        return null;
    }
}