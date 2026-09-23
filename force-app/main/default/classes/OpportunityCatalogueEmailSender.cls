/**
 * @description Sends the inventory catalogue link email for Arelia Opportunity records.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class OpportunityCatalogueEmailSender {
    private static final String ERROR_UNSUPPORTED_RECORD_TYPE =
        'Catalogue link can be sent only for Arelia opportunities.';
    private static final String TEMPLATE_DEVELOPER_NAME = 'Opportunity_Catalogue_Link';

    /**
     * @description Sends the catalogue link email for an Arelia Opportunity.
     * @param oppId Opportunity Id selected from the quick action.
     * @param forceSend When true, resends even when the catalogue link was already sent.
     */
    @AuraEnabled
    public static void sendCatalogueEmail(Id oppId, Boolean forceSend) {
        Opportunity opp = queryAreliaOpportunity(oppId);

        // Architecture Manager approval check.
        if (!opp.Architecture_Manager_Approval__c) {
            throw new AuraHandledException(
                'Catalogue link can be sent only after Architecture Manager approval.'
            );
        }

        // Feasibility check for resend
        if (opp.Catalogue_Link_Sent__c && !forceSend) {
            throw new AuraHandledException('ALREADY_SENT');
        }

        if (String.isBlank(opp.Email__c)) {
            throw new AuraHandledException('Email is missing on Opportunity.');
        }

        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = :TEMPLATE_DEVELOPER_NAME
            LIMIT 1
        ];

        String catalogueLink =
            Label.Arelia_Site_Label +
            Label.Inventory_Catalogue_Site_Base +
            '?id=' + opp.Id;

        String htmlBody = tpl.HtmlValue
            .replace('{{{CustomerName}}}', opp.Lead_Name__c)
            .replace('{{{catalogueLink}}}', catalogueLink);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ opp.Email__c });
        msg.setSubject(tpl.Subject);
        msg.setHtmlBody(htmlBody);
        msg.setWhatId(opp.Id);
        msg.setSaveAsActivity(true);
        AreliaUtility.setOrgWideEmailAddress(msg, System.Label.Arelia_OWD);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });

        // Mark as sent (always true after first send)
        if (!opp.Catalogue_Link_Sent__c) {
            opp.Catalogue_Link_Sent__c = true;
            update opp;
        }
    }

    private static Opportunity queryAreliaOpportunity(Id oppId) {
        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
        if (areliaOpportunityRecordTypeId == null) {
            throw new AuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }

        // Keep the Arelia Record Type requirement in SOQL so unsupported Opportunities do not proceed.
        List<Opportunity> opportunities = [
            SELECT Id, Lead_Name__c, Email__c, Catalogue_Link_Sent__c,
                Architecture_Manager_Approval__c
            FROM Opportunity
            WHERE Id = :oppId
            AND RecordTypeId = :areliaOpportunityRecordTypeId
            LIMIT 1
        ];

        if (opportunities.isEmpty()) {
            throw new AuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }

        return opportunities[0];
    }
}