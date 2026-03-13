/**
 * @description       : Handles Vendor Abscond Logic
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 01-13-2026
**/
public with sharing class HandleVendorAbscondController { 

    // -------------------------------------------------------------------
    // 🔹 DTO Classes
    // -------------------------------------------------------------------
    public class EmailTemplateDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String folderName;
    }

    public class VendorWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    public class VendorClientDTO {
        @AuraEnabled public List<VendorWrapper> vendors;
        @AuraEnabled public String clientEmail;
        @AuraEnabled public String clientName;
    }

    // -------------------------------------------------------------------
    // 🔹 Folder Name Constant
    // -------------------------------------------------------------------
    @TestVisible 
    private static String EMAIL_TEMPLATE_FOLDER_NAME = Label.Arelia_Living_Vendor_Abscond_Templates;

    @AuraEnabled(cacheable=true)
    public static List<EmailTemplateDTO> getEmailTemplatesByFolder() {
        List<EmailTemplateDTO> templates = new List<EmailTemplateDTO>();
        
        String folderToQuery = EMAIL_TEMPLATE_FOLDER_NAME;

        for (EmailTemplate et : [
            SELECT Id, Name, DeveloperName, Folder.DeveloperName, Folder.Name
            FROM EmailTemplate
            WHERE Folder.Name = :folderToQuery
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ]) {
            EmailTemplateDTO dto = new EmailTemplateDTO();
            dto.id = et.Id;
            dto.name = et.Name;
            dto.developerName = et.DeveloperName;
            dto.folderName = et.Folder != null ? et.Folder.Name : null;
            templates.add(dto);
        }
        return templates;
    }

    // -------------------------------------------------------------------
    // 🔹 Get Abscond Vendors & Client Email
    // -------------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static VendorClientDTO getAbscondVendorsAndClient(Id opportunityId) {
        VendorClientDTO dto = new VendorClientDTO();
        dto.vendors = new List<VendorWrapper>();

        // Fetch abscond vendors
        List<Vendor_Assignment__c> assignments = [
            SELECT Id, Vendor__r.Name, Vendor__r.Email__c, Status__c
            FROM Vendor_Assignment__c
            WHERE Opportunity__c = :opportunityId
            AND Status__c = 'Abscond'
            AND Vendor__r.Email__c != null
        ];

        for (Vendor_Assignment__c va : assignments) {
            VendorWrapper v = new VendorWrapper();
            v.id = va.Id;
            v.name = va.Vendor__r.Name;
            v.email = va.Vendor__r.Email__c;
            dto.vendors.add(v);
        }

        // Fetch client name & email from Opportunity fields or Account
        Opportunity opp = [
            SELECT Id, 
                   Lead_Name__c, 
                   Email__c, 
                   AccountId, 
                   Account.Name, 
                   Account.Email__c, 
                   Account.PersonEmail
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        // Priority: Lead fields → Account
        if (String.isNotBlank(opp.Email__c)) {
            dto.clientEmail = opp.Email__c;
            dto.clientName = opp.Lead_Name__c;
        } else if (opp.AccountId != null) {
            dto.clientEmail = opp.Account.Email__c != null 
                ? opp.Account.Email__c 
                : opp.Account.PersonEmail;
            dto.clientName = opp.Account.Name;
        }

        return dto;
    }

    // -------------------------------------------------------------------
    // 🔹 Send Email (Supports multiple recipients)
    // -------------------------------------------------------------------
    @AuraEnabled
    public static String sendEmail(Id templateId, List<String> recipientEmails, Id opportunityId, String templateType, List<Id> vendorAssignmentIds) {
        if (templateId == null) {
            throw new AuraHandledException('Template Id is required.');
        }
        if (recipientEmails == null || recipientEmails.isEmpty()) {
            throw new AuraHandledException('Recipient email is required.');
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // 🔹 Create dummy contact for merge context
        Contact dummyContact = new Contact(LastName = 'TempRecipient', Email = 'temp@example.com');
        insert dummyContact;

        try {
            // 🔹 Loop through recipients
            for (Integer i = 0; i < recipientEmails.size(); i++) {
                String toEmail = recipientEmails[i];
                if (String.isBlank(toEmail)) continue;

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(templateId);
                mail.setTargetObjectId(dummyContact.Id);
                mail.setToAddresses(new String[] { toEmail });

                // ✅ Use correct record for WhatId
                if (templateType == 'Vendor' && vendorAssignmentIds != null && vendorAssignmentIds.size() > i) {
                    mail.setWhatId(vendorAssignmentIds[i]);
                } else {
                    mail.setWhatId(opportunityId);
                }

                mail.setTreatTargetObjectAsRecipient(false);
                
                if (templateType == 'Vendor') {
                    mail.setSaveAsActivity(false); // 🔥 skip creating Task for vendor mail
                } else {
                    mail.setSaveAsActivity(true);
                }
                emails.add(mail);
            }

            if (emails.isEmpty()) {
                throw new AuraHandledException('No valid emails found.');
            }

            // 🔹 Send
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

            for (Messaging.SendEmailResult res : results) {
                if (!res.isSuccess()) {
                    String err = 'Failed to send email.';
                    if (res.getErrors() != null && res.getErrors().size() > 0) {
                        err += ' ' + res.getErrors()[0].getMessage();
                    }
                    throw new AuraHandledException(err);
                }
            }
        } finally {
            // Clean dummy (Always clean up even if exception occurs)
            if(dummyContact.Id != null) delete dummyContact;
        }

        return 'SUCCESS';
    }
}