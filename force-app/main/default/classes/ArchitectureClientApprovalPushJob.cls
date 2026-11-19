public without sharing class ArchitectureClientApprovalPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> opportunityIds;

    public ArchitectureClientApprovalPushJob(
        Set<Id> opportunityIds
    ) {
        this.opportunityIds =
            opportunityIds == null
                ? new Set<Id>()
                : new Set<Id>(opportunityIds);
    }

    public void execute(QueueableContext context) {

        if (opportunityIds.isEmpty()) {
            return;
        }

        // =====================================================
        // 1. GET OPPORTUNITIES
        // =====================================================

        Map<Id, Opportunity> opportunityMap =
            new Map<Id, Opportunity>([
                SELECT
                    Id,
                    Name,
                    Primary_Contact__c,
                    Architecture_Client_Approval_Sent__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);

        if (opportunityMap.isEmpty()) {
            return;
        }

        // =====================================================
        // 2. FIND CONVERTED LEADS FOR EACH OPPORTUNITY
        // =====================================================

        List<Lead> convertedLeads = [
            SELECT
                Id,
                IsConverted,
                ConvertedOpportunityId,
                Portal_Account_Key__c,
                CreatedDate
            FROM Lead
            WHERE ConvertedOpportunityId IN :opportunityIds
        ];

        Map<Id, Id> leadIdByOpportunity =
            new Map<Id, Id>();

        Map<Id, Id> accountByLead =
            new Map<Id, Id>();

        Set<Id> accountLeadIds =
            new Set<Id>();

        Set<Id> tokenOwnerLeadIds =
            new Set<Id>();

        for (Lead leadRecord : convertedLeads) {

            if (
                !leadRecord.IsConverted ||
                leadRecord.ConvertedOpportunityId == null
            ) {
                continue;
            }

            Id accountLeadId =
                resolveAccountLeadId(leadRecord);

            leadIdByOpportunity.put(
                leadRecord.ConvertedOpportunityId,
                leadRecord.Id
            );

            accountByLead.put(
                leadRecord.Id,
                accountLeadId
            );

            accountLeadIds.add(accountLeadId);

            // Original customer Lead.
            tokenOwnerLeadIds.add(accountLeadId);

            // Also support a token attached to this Lead.
            tokenOwnerLeadIds.add(leadRecord.Id);
        }

        if (leadIdByOpportunity.isEmpty()) {

            System.debug(
                LoggingLevel.WARN,
                'ARCHITECTURE PUSH: No converted Leads found.'
            );

            return;
        }

        // =====================================================
        // 3. GET ALL PROJECT LEADS FOR NUMBERING
        // =====================================================

        Set<String> accountKeys =
            new Set<String>();

        for (Id accountId : accountLeadIds) {
            accountKeys.add(
                String.valueOf(accountId)
            );
        }

        List<Lead> accountProjects = [
            SELECT
                Id,
                Portal_Account_Key__c,
                CreatedDate
            FROM Lead
            WHERE Id IN :accountLeadIds
               OR Portal_Account_Key__c IN :accountKeys
            ORDER BY CreatedDate ASC, Id ASC
        ];

        Map<Id, Integer> projectNumberByLead =
            new Map<Id, Integer>();

        Map<Id, Integer> projectCountByAccount =
            new Map<Id, Integer>();

        for (Lead projectLead : accountProjects) {

            Id accountId =
                resolveAccountLeadId(projectLead);

            if (!accountLeadIds.contains(accountId)) {
                continue;
            }

            Integer projectNumber = 1;

            if (
                projectCountByAccount.containsKey(
                    accountId
                )
            ) {
                projectNumber =
                    projectCountByAccount.get(accountId) + 1;
            }

            projectCountByAccount.put(
                accountId,
                projectNumber
            );

            projectNumberByLead.put(
                projectLead.Id,
                projectNumber
            );
        }

        // =====================================================
        // 4. GET LATEST ARCHITECTURE DESIGN
        // =====================================================

        List<Architecture_Design__c>
            architectureRecords = [

                SELECT
                    Id,
                    Name,
                    Opportunity__c,
                    Architecture_Budget__c,
                    Comments__c,
                    External_File_Link__c,
                    Public_Image_Url__c,
                    Related_File_Id__c,
                    Status__c,
                    CreatedDate

                FROM Architecture_Design__c

                WHERE Opportunity__c IN :opportunityIds

                ORDER BY CreatedDate DESC
            ];

        Map<Id, Architecture_Design__c>
            architectureByOpportunity =
                new Map<
                    Id,
                    Architecture_Design__c
                >();

        for (
            Architecture_Design__c design :
            architectureRecords
        ) {

            if (design.Opportunity__c == null) {
                continue;
            }

            // Newest design for each Opportunity.
            if (
                !architectureByOpportunity.containsKey(
                    design.Opportunity__c
                )
            ) {
                architectureByOpportunity.put(
                    design.Opportunity__c,
                    design
                );
            }
        }

        // =====================================================
        // 5. GET ACCOUNT-WIDE PROSPECT DEVICE TOKENS
        // =====================================================

        List<Prospect_Device_Token__c>
            deviceTokens = [

                SELECT
                    Id,
                    Prospect_Lead__c,
                    FCM_Token__c,
                    Platform__c,
                    Active__c,
                    Last_Seen__c

                FROM Prospect_Device_Token__c

                WHERE
                    Prospect_Lead__c IN :tokenOwnerLeadIds
                    AND Active__c = true

                ORDER BY Last_Seen__c DESC
                NULLS LAST
            ];

        Map<Id, Prospect_Device_Token__c>
            latestDeviceByLead =
                new Map<
                    Id,
                    Prospect_Device_Token__c
                >();

        for (
            Prospect_Device_Token__c device :
            deviceTokens
        ) {

            if (
                device.Prospect_Lead__c == null ||
                String.isBlank(device.FCM_Token__c)
            ) {
                continue;
            }

            // Preserve the most recently seen token.
            if (
                !latestDeviceByLead.containsKey(
                    device.Prospect_Lead__c
                )
            ) {
                latestDeviceByLead.put(
                    device.Prospect_Lead__c,
                    device
                );
            }
        }

        // =====================================================
        // 6. SEND PROJECT-SPECIFIC ARCHITECTURE PUSH
        // =====================================================

        Integer successfulCount = 0;
        Integer failedCount = 0;

        for (Id opportunityId : opportunityIds) {

            Opportunity opp =
                opportunityMap.get(opportunityId);

            if (
                opp == null ||
                opp.Architecture_Client_Approval_Sent__c
                    != true
            ) {
                continue;
            }

            Id leadId =
                leadIdByOpportunity.get(opportunityId);

            if (leadId == null) {

                System.debug(
                    LoggingLevel.WARN,
                    'ARCHITECTURE PUSH: ' +
                    'No converted Lead for Opportunity: ' +
                    opportunityId
                );

                continue;
            }

            Id accountLeadId =
                accountByLead.get(leadId);

            Integer projectNumber =
                projectNumberByLead.get(leadId);

            Architecture_Design__c design =
                architectureByOpportunity.get(
                    opportunityId
                );

            if (design == null) {

                System.debug(
                    LoggingLevel.WARN,
                    'ARCHITECTURE PUSH: ' +
                    'No Architecture Design for Opportunity: ' +
                    opportunityId
                );

                continue;
            }

            // Find token registered on original customer Lead.
            Prospect_Device_Token__c device =
                latestDeviceByLead.get(accountLeadId);

            // Fallback to token registered on event Lead.
            if (device == null) {
                device = latestDeviceByLead.get(leadId);
            }

            if (
                device == null ||
                String.isBlank(device.FCM_Token__c)
            ) {

                System.debug(
                    LoggingLevel.WARN,
                    'ARCHITECTURE PUSH: No active Prospect token. ' +
                    'Lead=' + leadId +
                    ', Account=' + accountLeadId
                );

                continue;
            }

            // Leave room for Firebase authentication callouts.
            if (
                Limits.getCallouts() >=
                    Limits.getLimitCallouts() - 2
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'ARCHITECTURE PUSH: Callout limit reached.'
                );
                break;
            }

            try {

                sendNotification(
                    device.FCM_Token__c,
                    leadId,
                    accountLeadId,
                    projectNumber,
                    opp,
                    design
                );

                successfulCount++;

            } catch (Exception ex) {

                failedCount++;

                System.debug(
                    LoggingLevel.ERROR,
                    'ARCHITECTURE PUSH FAILED. ' +
                    'Opportunity=' + opportunityId +
                    ', Error=' + ex.getMessage()
                );
            }
        }

        System.debug(
            LoggingLevel.INFO,
            'ARCHITECTURE MULTI-PROJECT PUSH COMPLETE. ' +
            'Successful=' + successfulCount +
            ', Failed=' + failedCount
        );
    }

    // =========================================================
    // 7. RESOLVE ORIGINAL ACCOUNT LEAD
    // =========================================================

    private static Id resolveAccountLeadId(
        Lead leadRecord
    ) {

        if (
            String.isBlank(
                leadRecord.Portal_Account_Key__c
            )
        ) {
            return leadRecord.Id;
        }

        try {

            Id accountLeadId =
                (Id) leadRecord.Portal_Account_Key__c.trim();

            if (
                accountLeadId.getSObjectType() ==
                    Lead.SObjectType
            ) {
                return accountLeadId;
            }

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.WARN,
                'ARCHITECTURE PUSH: Invalid account key. ' +
                'Lead=' + leadRecord.Id
            );
        }

        return leadRecord.Id;
    }

    // =========================================================
    // 8. SEND FIREBASE PUSH
    // =========================================================

    private static void sendNotification(
        String fcmToken,
        Id leadId,
        Id accountLeadId,
        Integer projectNumber,
        Opportunity opp,
        Architecture_Design__c design
    ) {

        String title =
            'Architecture Design Ready for Review';

        // Add project number to notification title.
        if (projectNumber != null) {

            title =
                'Arelia - Project ' +
                String.valueOf(projectNumber) +
                ': Architecture Design Ready for Review';
        }

        // Preserve existing notification body.
        String body =
            'Your architecture design is ready for review. ' +
            'Tap to view the design and submit your response.';

        // =====================================================
        // PRESERVE EXISTING FLUTTER ROUTING
        // =====================================================

        Map<String, String> payload =
            new Map<String, String>{

                'recipientType' =>
                    'prospect',

                'notificationType' =>
                    'ARCHITECTURE_DESIGN_UPLOADED',

                'actionType' =>
                    'OPEN_ARCHITECTURE_DESIGN',

                'route' =>
                    'prospect_architecture_design',

                // Actual Lead associated with this Opportunity.
                'leadId' =>
                    String.valueOf(leadId),

                // Original customer account Lead.
                'accountLeadId' =>
                    String.valueOf(accountLeadId),

                'opportunityId' =>
                    String.valueOf(opp.Id),

                'designId' =>
                    String.valueOf(design.Id),

                'id' =>
                    'ARCHITECTURE_DESIGN_UPLOADED:' +
                    String.valueOf(design.Id),

                'title' =>
                    title,

                'body' =>
                    body
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

        // Send using existing Firebase service.
        FirebasePushService.sendPushToToken(
            fcmToken,
            title,
            body,
            payload
        );

        System.debug(
            LoggingLevel.INFO,
            'ARCHITECTURE MULTI-PROJECT PUSH SENT. ' +
            'Lead=' + leadId +
            ', Account=' + accountLeadId +
            ', Project=' + projectNumber +
            ', Opportunity=' + opp.Id +
            ', Design=' + design.Id
        );
    }
}