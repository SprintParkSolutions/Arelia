public with sharing class VendorAbscondEmailController {

    // DTO for Email Template
    public class EmailTemplateDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String body { get; set; }

        public EmailTemplateDTO(Id id, String name, String subject, String body) {
            this.id = id;
            this.name = name;
            this.subject = subject;
            this.body = body;
        }
    }

    // 1. Get Email Templates from Folder
    @AuraEnabled(cacheable=true)
    public static List<EmailTemplateDTO> getEmailTemplatesByFolder(String folderName) {
        List<EmailTemplateDTO> dtos = new List<EmailTemplateDTO>();
        for (EmailTemplate t : [
            SELECT Id, Name, Subject, HtmlValue 
            FROM EmailTemplate 
            WHERE Folder.Name = :folderName 
              AND IsActive = true
        ]) {
            dtos.add(new EmailTemplateDTO(t.Id, t.Name, t.Subject, t.HtmlValue));
        }
        return dtos;
    }

    // 2. Get Abscond Vendors
    @AuraEnabled(cacheable=true)
    public static List<VendorWrapper> getVendorsByOpportunity(Id opportunityId) {
        List<VendorWrapper> wrappers = new List<VendorWrapper>();
        for (Vendor_Assignment__c va : [
            SELECT Vendor__r.Id, Vendor__r.Name, Vendor__r.Email__c
            FROM Vendor_Assignment__c
            WHERE Opportunity__c = :opportunityId
              AND Status__c = 'Abscond'
              AND Vendor__r.Email__c != null
        ]) {
            wrappers.add(new VendorWrapper(
                va.Vendor__r.Id,
                va.Vendor__r.Name,
                va.Vendor__r.Email__c
            ));
        }
        return wrappers;
    }

    // 3. Get Client (Lead) from Opportunity.Lead_Name__c and Email__c
    @AuraEnabled(cacheable=true)
    public static LeadWrapper getClientByOpportunity(Id opportunityId) {
        try {
            Opportunity opp = [
                SELECT Lead_Name__c, Email__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            if (String.isNotBlank(opp.Email__c)) {
                return new LeadWrapper(
                    null, // id not needed
                    opp.Lead_Name__c,
                    opp.Email__c
                );
            }
        } catch (Exception e) {
            System.debug('Error loading client fields: ' + e.getMessage());
        }
        return null;
    }

    // 4. Send Email
    @AuraEnabled
    public static void sendEmail(String toAddress, String subject, String body) {
        if (String.isBlank(toAddress)) {
            throw new AuraHandledException('Recipient email is required.');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toAddress });
        mail.setSubject(subject);
        mail.setHtmlBody(body);
        mail.setTreatBodiesAsTemplate(true);
        mail.setSaveAsActivity(false);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    // Wrapper Classes
    public class VendorWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }

        public VendorWrapper(Id id, String name, String email) {
            this.id = id;
            this.name = name;
            this.email = email;
        }
    }

    public class LeadWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }

        public LeadWrapper(Id id, String name, String email) {
            this.id = id;
            this.name = name;
            this.email = email;
        }
    }
}