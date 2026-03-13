public with sharing class OpportunityCatalogueEmailSender {

    @AuraEnabled
    public static void sendCatalogueEmail(Id oppId, Boolean forceSend) {

        Opportunity opp = [
            SELECT Id, Lead_Name__c, Email__c, Catalogue_Link_Sent__c,Architecture_Manager_Approval__c
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

// Architecture Manager approval check
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
            WHERE DeveloperName = 'Opportunity_Catalogue_Link'
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
        msg.setOrgWideEmailAddressId(getOWD());

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });

        // Mark as sent (always true after first send)
        if (!opp.Catalogue_Link_Sent__c) {
            opp.Catalogue_Link_Sent__c = true;
            update opp;
        }
    }

    private static Id getOWD() {
        OrgWideEmailAddress owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true
            LIMIT 1
        ];
        return owea.Id;
    }
}


/*public with sharing class OpportunityCatalogueEmailSender {

    public static void sendCatalogueEmail(List<Id> oppIds) {

        List<Opportunity> oppList = [
            SELECT Id, Lead_Name__c, Email__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];

        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = 'Opportunity_Catalogue_Link'
            LIMIT 1
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : oppList) { 

            
            String inventoryCatalogueLink = Label.Arelia_Site_Label+ Label.Inventory_Catalogue_Site_Base + '?id=' + opp.Id;

           String html = tpl.HtmlValue
                 .replace('{{{CustomerName}}}', opp.Lead_Name__c)
               
                   .replace('{{{catalogueLink}}}', inventoryCatalogueLink);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ opp.Email__c });
            msg.setSubject(tpl.Subject);
            msg.setHtmlBody(html);
            msg.setWhatId(opp.Id);
            msg.setSaveAsActivity(true);
            msg.setOrgWideEmailAddressId(getOWD());
            emails.add(msg);
        }

        Messaging.sendEmail(emails);
    }

    private static Id getOWD() {
        List<OrgWideEmailAddress> listOWEA = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true LIMIT 1
        ];
        return !listOWEA.isEmpty() ? listOWEA[0].Id : null;
    }
}*/