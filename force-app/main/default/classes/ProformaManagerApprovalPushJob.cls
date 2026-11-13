public without sharing class ProformaManagerApprovalPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> invoiceIds;

    private static final Integer MAX_PUSH_ATTEMPTS = 90;

    public ProformaManagerApprovalPushJob(Set<Id> invoiceIds) {
        this.invoiceIds = invoiceIds == null
            ? new Set<Id>()
            : new Set<Id>(invoiceIds);
    }

    public void execute(QueueableContext context) {

        if (invoiceIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PROFORMA MANAGER: No invoice IDs.'
            );
            return;
        }

        // =====================================================
        // 1. GET MANAGER APPROVED PROFORMA INVOICES
        // =====================================================

        List<Proforma_Invoice__c> invoices = [
            SELECT
                Id,
                Name,
                Opportunity__c,
                Project__c,
                Secure_Token__c,
                Status__c,
                Manager_Approval__c,
                Manager_Comments__c,
                Proforma_Invoice_Approved_Date__c
            FROM Proforma_Invoice__c
            WHERE Id IN :invoiceIds
              AND Manager_Approval__c = true
              AND Opportunity__c != null
              AND Proforma_Invoice_Approved_Date__c != null
            ORDER BY Id
        ];

        if (invoices.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PROFORMA MANAGER: No approved invoices.'
            );
            return;
        }

        Set<Id> opportunityIds = new Set<Id>();

        for (Proforma_Invoice__c inv : invoices) {
            opportunityIds.add(inv.Opportunity__c);
        }

        // =====================================================
        // 2. FIND THE ACTUAL CONVERTED PROJECT LEADS
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
              AND ConvertedOpportunityId IN :opportunityIds
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
                'PROFORMA MANAGER: No converted Leads found.'
            );
            return;
        }

        // =====================================================
        // 3. GET ALL RELATED PROJECT LEADS
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

            projectCountByAccount.put(accountId, 0);

            contactIdsByAccount.put(
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

            if (
                !originalAccountLeadIds.contains(accountId)
            ) {
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
                contactIdsByAccount.get(accountId).add(
                    projectLead.ConvertedContactId
                );
            }
        }

        // =====================================================
        // 5. GET PROSPECT TOKENS ACCOUNT-WIDE
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
        // 6. GET CONVERTED CONTACT TOKENS ACCOUNT-WIDE
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
        // 7. SEND APPROVAL NOTIFICATION PER INVOICE
        // =====================================================

        Integer attempted = 0;
        Integer completed = 0;
        Integer failed = 0;

        Boolean limitReached = false;

        for (Proforma_Invoice__c inv : invoices) {

            Lead prospect =
                leadByOpportunity.get(inv.Opportunity__c);

            if (prospect == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROFORMA MANAGER: Lead missing. Invoice=' +
                    inv.Id
                );
                continue;
            }

            // Preserve the original secure-token condition.
            if (String.isBlank(inv.Secure_Token__c)) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROFORMA MANAGER: Secure token missing. Invoice=' +
                    inv.Id
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

            Set<String> recipients =
                tokensByAccount.get(accountLeadId);

            if (
                recipients == null ||
                recipients.isEmpty()
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'PROFORMA MANAGER: No active device tokens. ' +
                    'Lead=' + prospect.Id +
                    ', Account=' + accountLeadId
                );
                continue;
            }

            // =================================================
            // 8. PROJECT-SPECIFIC NOTIFICATION
            // =================================================

            String title =
                'Arelia - ' + projectLabel +
                ': Proforma Invoice Approved';

            // Keep the existing notification message.
            String body =
                'Your Proforma Invoice has been approved by the manager. ' +
                'Tap to view the details.';

            String notificationType =
                'PROFORMA_MANAGER_APPROVED';

            Map<String, String> payload =
                new Map<String, String>{

                    'recipientType' =>
                        'prospect',

                    'notificationType' =>
                        notificationType,

                    'type' =>
                        notificationType,

                    'actionType' =>
                        'OPEN_PROFORMA_INVOICE',

                    'route' =>
                        'prospect_proforma_invoice',

                    // Actual Lead related to this invoice.
                    'leadId' =>
                        String.valueOf(prospect.Id),

                    // Original customer login Lead.
                    'accountLeadId' =>
                        String.valueOf(accountLeadId),

                    // Converted Contact of actual project.
                    'contactId' =>
                        prospect.ConvertedContactId == null
                            ? ''
                            : String.valueOf(
                                prospect.ConvertedContactId
                            ),

                    // Opportunity of the approved invoice.
                    'opportunityId' =>
                        String.valueOf(inv.Opportunity__c),

                    // Exact approved invoice.
                    'invoiceId' =>
                        String.valueOf(inv.Id),

                    // Preserve the access token required by Flutter.
                    'secureToken' =>
                        inv.Secure_Token__c,

                    'recordId' =>
                        String.valueOf(inv.Id),

                    'id' =>
                        notificationType + ':' +
                        String.valueOf(inv.Id),

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

            if (projectLabel.startsWith('Project ')) {
                payload.put(
                    'projectNumber',
                    projectLabel.substring(8)
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'PROFORMA MANAGER MULTI-PROJECT PUSH: ' +
                projectLabel +
                ', Invoice=' + inv.Id +
                ', Lead=' + prospect.Id +
                ', Account=' + accountLeadId +
                ', Tokens=' + recipients.size()
            );

            // =================================================
            // 9. SEND TO UNIQUE ACTIVE FCM TOKENS
            // =================================================

            for (String token : recipients) {

                if (String.isBlank(token)) {
                    continue;
                }

                // Leave callout headroom for Firebase service.
                if (
                    attempted >= MAX_PUSH_ATTEMPTS ||
                    Limits.getCallouts() >=
                        Limits.getLimitCallouts() - 2
                ) {
                    limitReached = true;
                    System.debug(
                        LoggingLevel.WARN,
                        'PROFORMA MANAGER: Callout safety limit reached.'
                    );
                    break;
                }

                attempted++;

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
                        'PROFORMA MANAGER PUSH SENT. ' +
                        'Project=' + projectLabel +
                        ', Invoice=' + inv.Id +
                        ', Lead=' + prospect.Id
                    );

                } catch (Exception ex) {

                    failed++;

                    System.debug(
                        LoggingLevel.ERROR,
                        'PROFORMA MANAGER PUSH FAILED. ' +
                        'Invoice=' + inv.Id +
                        ', Error=' + ex.getMessage()
                    );
                }
            }

            if (limitReached) {
                break;
            }
        }

        // =====================================================
        // 10. FINAL EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            'PROFORMA MANAGER MULTI-PROJECT PUSH SUMMARY: ' +
            'Invoices=' + invoices.size() +
            ', ProspectTokens=' + prospectTokenRecords +
            ', MobileTokens=' + mobileTokenRecords +
            ', Attempts=' + attempted +
            ', Completed=' + completed +
            ', Failed=' + failed +
            ', CalloutLimitReached=' + limitReached
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
                'PROFORMA MANAGER: Invalid account key. Lead=' +
                projectLead.Id
            );
        }

        return projectLead.Id;
    }
}