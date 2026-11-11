public without sharing class LeadSupervisorAssignedPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> leadIds;

    public LeadSupervisorAssignedPushJob(Set<Id> leadIds) {
        this.leadIds = leadIds == null
            ? new Set<Id>()
            : new Set<Id>(leadIds);
    }

    public void execute(QueueableContext context) {

        System.debug('====================================');
        System.debug('SUPERVISOR ASSIGNED PUSH JOB STARTED');
        System.debug('LEAD IDS: ' + leadIds);
        System.debug('JOB ID: ' + context.getJobId());
        System.debug('====================================');

        if (leadIds.isEmpty()) {
            return;
        }

        // =====================================================
        // 1. GET LEADS AND SUPERVISOR DETAILS
        // =====================================================

        List<Lead> leads = [
            SELECT Id,
                   Name,
                   IsConverted,
                   Portal_Account_Key__c,
                   Supervisor_User__c,
                   Supervisor_User__r.Name,
                   Supervisor_User_Email__c,
                   Supervisor_User_Phone__c
            FROM Lead
            WHERE Id IN :leadIds
        ];

        if (leads.isEmpty()) {
            return;
        }

        Set<Id> validLeadIds = new Set<Id>();
        Map<Id, Lead> leadMap = new Map<Id, Lead>();

        // Each event Lead belongs to one original account Lead.
        Map<Id, Id> accountByEventLead =
            new Map<Id, Id>();

        Set<Id> accountLeadIds = new Set<Id>();

        // =====================================================
        // 2. VALIDATE SUPERVISOR ASSIGNMENTS
        // =====================================================

        for (Lead prospect : leads) {

            // Preserve original behavior:
            // do not send supervisor-assigned pushes
            // for already converted Leads.
            if (prospect.IsConverted == true) {
                continue;
            }

            if (prospect.Supervisor_User__c == null) {
                continue;
            }

            validLeadIds.add(prospect.Id);
            leadMap.put(prospect.Id, prospect);

            Id accountLeadId = prospect.Id;

            String accountKey =
                prospect.Portal_Account_Key__c;

            if (!String.isBlank(accountKey)) {
                try {
                    Id parsedKey = (Id) accountKey.trim();

                    if (parsedKey.getSObjectType() ==
                        Lead.SObjectType) {
                        accountLeadId = parsedKey;
                    }
                } catch (Exception ex) {
                    System.debug(
                        LoggingLevel.WARN,
                        'INVALID ACCOUNT KEY FOR LEAD ' +
                        prospect.Id + ': ' + accountKey
                    );
                }
            }

            accountByEventLead.put(
                prospect.Id,
                accountLeadId
            );

            accountLeadIds.add(accountLeadId);
        }

        if (validLeadIds.isEmpty()) {
            System.debug(
                'NO ELIGIBLE SUPERVISOR ASSIGNMENTS.'
            );
            return;
        }

        // =====================================================
        // 3. GET ALL LEADS BELONGING TO THESE ACCOUNTS
        // =====================================================

        Set<String> accountKeyStrings =
            new Set<String>();

        for (Id accountId : accountLeadIds) {
            accountKeyStrings.add(String.valueOf(accountId));
        }

        List<Lead> projectLeads = [
            SELECT Id,
                   Name,
                   CreatedDate,
                   Portal_Account_Key__c
            FROM Lead
            WHERE Id IN :accountLeadIds
               OR Portal_Account_Key__c
                    IN :accountKeyStrings
            ORDER BY CreatedDate ASC, Id ASC
        ];

        // Map every project Lead to its original
        // account Lead.
        Map<Id, Id> accountByProjectLead =
            new Map<Id, Id>();

        // Map each account to all of its project Leads.
        Map<Id, List<Id>> projectsByAccount =
            new Map<Id, List<Id>>();

        for (Id accountId : accountLeadIds) {
            projectsByAccount.put(
                accountId,
                new List<Id>()
            );
        }

        // =====================================================
        // 4. BUILD PROJECT ROSTER
        // =====================================================

        for (Lead projectLead : projectLeads) {

            Id accountId = projectLead.Id;

            if (!String.isBlank(
                projectLead.Portal_Account_Key__c
            )) {
                try {
                    Id parsedId = (Id)
                        projectLead.Portal_Account_Key__c.trim();

                    if (parsedId.getSObjectType() ==
                        Lead.SObjectType) {
                        accountId = parsedId;
                    }
                } catch (Exception ex) {
                    continue;
                }
            }

            if (!projectsByAccount.containsKey(accountId)) {
                continue;
            }

            accountByProjectLead.put(
                projectLead.Id,
                accountId
            );

            projectsByAccount.get(accountId)
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
        // 6. FIND ALL ACCOUNT-WIDE DEVICE TOKENS
        // =====================================================

        Set<Id> tokenLeadIds = new Set<Id>();

        tokenLeadIds.addAll(accountLeadIds);

        for (Lead projectLead : projectLeads) {
            if (
                accountByProjectLead.containsKey(
                    projectLead.Id
                )
            ) {
                tokenLeadIds.add(projectLead.Id);
            }
        }

        List<Prospect_Device_Token__c> devices = [
            SELECT Id,
                   Prospect_Lead__c,
                   FCM_Token__c,
                   Platform__c,
                   Active__c,
                   Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :tokenLeadIds
              AND Active__c = true
            ORDER BY Last_Seen__c DESC
        ];

        // Every customer account can have multiple
        // devices, but duplicate FCM tokens are removed.
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

            // The original account Lead can itself
            // have the registered device token.
            if (
                accountId == null &&
                accountLeadIds.contains(
                    device.Prospect_Lead__c
                )
            ) {
                accountId = device.Prospect_Lead__c;
            }

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
        // 7. SEND SUPERVISOR NOTIFICATIONS
        // =====================================================

        Integer successCount = 0;
        Integer failureCount = 0;

        for (Id leadId : validLeadIds) {

            Lead prospect = leadMap.get(leadId);

            Id accountId =
                accountByEventLead.get(leadId);

            Set<String> deliveryTokens =
                tokensByAccount.get(accountId);

            if (
                deliveryTokens == null ||
                deliveryTokens.isEmpty()
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'NO ACTIVE DEVICE TOKEN FOR LEAD: ' +
                    leadId +
                    ' ACCOUNT: ' + accountId
                );
                continue;
            }

            String projectLabel =
                projectLabelByLead.containsKey(leadId)
                    ? projectLabelByLead.get(leadId)
                    : 'Your Project';

            // =================================================
            // 8. NOTIFICATION TITLE AND BODY
            // =================================================

            String title =
                'Arelia - ' + projectLabel;

            String body =
                'A supervisor has now been assigned ' +
                'to your project. Tap to view the ' +
                'supervisor details and the latest updates.';

            // =================================================
            // 9. PROJECT-SPECIFIC NOTIFICATION PAYLOAD
            // =================================================

            Map<String, String> dataPayload =
                new Map<String, String>{

                    'recipientType' => 'prospect',

                    // The Lead that actually received
                    // the supervisor assignment.
                    'leadId' =>
                        String.valueOf(leadId),

                    // Customer account Lead.
                    'accountLeadId' =>
                        String.valueOf(accountId),

                    // Helps distinguish projects.
                    'projectLabel' => projectLabel,

                    'projectName' => projectLabel,

                    'notificationType' =>
                        'SUPERVISOR_ASSIGNED',

                    'actionType' =>
                        'OPEN_SUPERVISOR_DETAILS',

                    'route' =>
                        'prospect_supervisor_details',

                    'supervisorId' =>
                        String.valueOf(
                            prospect.Supervisor_User__c
                        ),

                    'supervisorName' =>
                        prospect.Supervisor_User__r != null
                            ? prospect.Supervisor_User__r.Name
                            : '',

                    'supervisorEmail' =>
                        String.isBlank(
                            prospect.Supervisor_User_Email__c
                        )
                            ? ''
                            : prospect.Supervisor_User_Email__c,

                    'supervisorPhone' =>
                        String.isBlank(
                            prospect.Supervisor_User_Phone__c
                        )
                            ? ''
                            : prospect.Supervisor_User_Phone__c,

                    'title' => title,
                    'body' => body
                };

            System.debug(
                LoggingLevel.INFO,
                'SUPERVISOR PUSH: ' +
                projectLabel +
                ' lead=' + leadId +
                ' account=' + accountId +
                ' tokens=' + deliveryTokens.size()
            );

            // =================================================
            // 10. DELIVER TO CUSTOMER DEVICES
            // =================================================

            for (String fcmToken : deliveryTokens) {

                // Reserve some HTTP callout headroom.
                if (
                    Limits.getCallouts() >=
                    Limits.getLimitCallouts() - 2
                ) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'CALLOUT LIMIT APPROACHING. ' +
                        'REMAINING NOTIFICATIONS ' +
                        'WERE NOT PROCESSED.'
                    );
                    return;
                }

                try {

                    FirebasePushService.sendPushToToken(
                        fcmToken,
                        title,
                        body,
                        dataPayload
                    );

                    successCount++;

                    System.debug(
                        LoggingLevel.INFO,
                        'SUPERVISOR PUSH ACCEPTED: ' +
                        projectLabel +
                        ' lead=' + leadId
                    );

                } catch (Exception ex) {

                    failureCount++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'SUPERVISOR PUSH FAILED: ' +
                        projectLabel +
                        ' lead=' + leadId +
                        ' error=' + ex.getMessage()
                    );
                }
            }
        }

        System.debug('====================================');
        System.debug('SUPERVISOR PUSH JOB COMPLETED');
        System.debug('SUCCESSFUL FCM SENDS: ' + successCount);
        System.debug('FAILED FCM SENDS: ' + failureCount);
        System.debug('====================================');
    }
}