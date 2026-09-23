/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : CareerPageController
 * Author          : <YourName>
 * Created Date    : May 15, 2026
 * Last Modified By: <YourName>
 * Last Modified On: May 15, 2026
 * Description     : Career page controller
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class CareerPageController {

    // 🔵 Fetch Job Offers
    @AuraEnabled(cacheable=true)
    public static List<Quokka__JobOffer__c> getJobOffers() {
        return [
            SELECT Id,
                   Quokka__Position__r.Name,
                   Quokka__JobSkillSet__r.Name,
                   Quokka__JobLocationSet__r.Name,
                   Quokka__JobContractType__c,
                   Quokka__JobOfferBody__c,
                   Quokka__ComplianceNotice__c,
                   Quokka__RecruitmentEndDate__c
            FROM Quokka__JobOffer__c
        ];
    }

    // 🔵 Create Job Application
    @AuraEnabled
    public static Quokka__JobApplication__c createJobApplication(
        Quokka__JobApplication__c jobApplication,
        String jobOfferId
    ) {
        if (String.isBlank(jobOfferId)) {
            throw new AuraHandledException('Job Offer ID is required.');
        }

        jobApplication.Quokka__JobOffer__c = jobOfferId;
        insert jobApplication;

        return jobApplication;
    }

    // 🔵 Dynamic Picklist Values
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(
        String objectName,
        String fieldName
    ) {
        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
        Schema.SObjectType objType = globalMap.get(objectName);

        if (objType == null) {
            return new List<Map<String, String>>();
        }

        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

        if (!fieldMap.containsKey(fieldName)) {
            return new List<Map<String, String>>();
        }

        Schema.DescribeFieldResult fieldResult =
            fieldMap.get(fieldName).getDescribe();

        List<Map<String, String>> picklistValues =
            new List<Map<String, String>>();

        for (Schema.PicklistEntry entry :
            fieldResult.getPicklistValues()) {

            picklistValues.add(
                new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                }
            );
        }

        return picklistValues;
    }

    // 🔵 Upload File + Send Email
    @AuraEnabled
    public static void uploadFile(
        Id jobApplicationId,
        String fileName,
        String fileBody
    ) {
        Blob fileBlob = EncodingUtil.base64Decode(fileBody);

        // Create file
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = fileBlob;
        insert cv;

        // Safely fetch ContentDocumentId
        List<ContentVersion> versions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            throw new AuraHandledException(
                'Uploaded file not found.'
            );
        }

        // Link file to Job Application
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.LinkedEntityId = jobApplicationId;
        cdl.ContentDocumentId = versions[0].ContentDocumentId;
        cdl.ShareType = 'I';
        insert cdl;

        // Send emails
        sendConfirmationEmail(jobApplicationId);
    }

    // 🔵 Email only (no file)
    @AuraEnabled
    public static void sendEmailOnly(Id jobApplicationId) {
        sendConfirmationEmail(jobApplicationId);
    }

    // 🔵 CORE EMAIL METHOD
    private static void sendConfirmationEmail(Id jobAppId) {
        try {
            // =====================================
            // 🔵 Fetch application
            // =====================================
            Quokka__JobApplication__c app = [
                SELECT Id,
                    Quokka__Email__c,
                    Quokka__FirstName__c,
                    Quokka__LastName__c
                FROM Quokka__JobApplication__c
                WHERE Id = :jobAppId
                LIMIT 1
            ];

            if (String.isBlank(app.Quokka__Email__c)) {
                return;
            }

            // =====================================
            // 🔵 CREATE TEMP CONTACT (duplicate-safe)
            // =====================================
            Id contactId;

            Contact tempContact = new Contact(
                FirstName = app.Quokka__FirstName__c,
                LastName = String.isBlank(app.Quokka__LastName__c)
                    ? 'Applicant'
                    : app.Quokka__LastName__c,
                Email = app.Quokka__Email__c
            );

            Database.SaveResult sr =
                Database.insert(tempContact, false);

            if (sr.isSuccess()) {
                contactId = sr.getId();
            } else {
                // If duplicate rule blocks insert,
                // reuse existing contact
                List<Contact> existingContacts = [
                    SELECT Id
                    FROM Contact
                    WHERE Email = :app.Quokka__Email__c
                    LIMIT 1
                ];

                if (!existingContacts.isEmpty()) {
                    contactId = existingContacts[0].Id;
                } else {
                    throw new AuraHandledException(
                        'Unable to create temporary contact.'
                    );
                }
            }

            // =====================================
            // 🔵 Get uploaded attachment
            // =====================================
            Messaging.EmailFileAttachment attachment;

            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :jobAppId
            ];

            Set<Id> docIds = new Set<Id>();

            for (ContentDocumentLink l : links) {
                docIds.add(l.ContentDocumentId);
            }

            if (!docIds.isEmpty()) {
                List<ContentVersion> files = [
                    SELECT Title, VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :docIds
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];

                if (!files.isEmpty()) {
                    attachment =
                        new Messaging.EmailFileAttachment();

                    attachment.setFileName(
                        files[0].Title
                    );

                    attachment.setBody(
                        files[0].VersionData
                    );
                }
            }

            // =====================================
            // 🔵 Org-wide email
            // =====================================
            String orgWideEmail =
                System.Label.Org_Wide_Email;

            Id orgWideEmailId = null;

            List<OrgWideEmailAddress> oweaList = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :orgWideEmail
                LIMIT 1
            ];

            if (!oweaList.isEmpty()) {
                orgWideEmailId = oweaList[0].Id;
            }

            // =====================================
            // 🔵 Applicant template
            // =====================================
            String templateApiName =
                System.Label.Job_Application_Email_Template;

            List<EmailTemplate> templates = [
                SELECT Id
                FROM EmailTemplate
                WHERE DeveloperName = :templateApiName
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                throw new AuraHandledException(
                    'Applicant email template not found: '
                    + templateApiName
                );
            }

            Messaging.SingleEmailMessage applicantMail =
                new Messaging.SingleEmailMessage();

            applicantMail.setTemplateId(
                templates[0].Id
            );

            applicantMail.setTargetObjectId(
                contactId
            );

            applicantMail.setTreatTargetObjectAsRecipient(
                false
            );

            applicantMail.setToAddresses(
                new List<String>{
                    app.Quokka__Email__c
                }
            );

            applicantMail.setWhatId(
                app.Id
            );

            applicantMail.setSaveAsActivity(
                false
            );

            if (orgWideEmailId != null) {
                applicantMail.setOrgWideEmailAddressId(
                    orgWideEmailId
                );
            }

            if (attachment != null) {
                applicantMail.setFileAttachments(
                    new List<Messaging.EmailFileAttachment>{
                        attachment
                    }
                );
            }

            // =====================================
            // 🔵 HR template
            // =====================================
            String hrTemplateName =
                System.Label.HR_Job_Email_Notification;

            String hrEmail =
                System.Label.HR_email;

            List<EmailTemplate> hrTemplates = [
                SELECT Id
                FROM EmailTemplate
                WHERE DeveloperName = :hrTemplateName
                LIMIT 1
            ];

            if (hrTemplates.isEmpty()) {
                throw new AuraHandledException(
                    'HR email template not found: '
                    + hrTemplateName
                );
            }

            Messaging.SingleEmailMessage hrMail =
                new Messaging.SingleEmailMessage();

            hrMail.setTemplateId(
                hrTemplates[0].Id
            );

            hrMail.setTargetObjectId(
                contactId
            );

            hrMail.setTreatTargetObjectAsRecipient(
                false
            );

            hrMail.setToAddresses(
                new List<String>{
                    hrEmail
                }
            );

            hrMail.setWhatId(
                app.Id
            );

            hrMail.setSaveAsActivity(
                false
            );

            if (orgWideEmailId != null) {
                hrMail.setOrgWideEmailAddressId(
                    orgWideEmailId
                );
            }

            if (attachment != null) {
                hrMail.setFileAttachments(
                    new List<Messaging.EmailFileAttachment>{
                        attachment
                    }
                );
            }

            // =====================================
            // 🔵 Send both emails
            // =====================================
            Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{
                    applicantMail,
                    hrMail
                }
            );

            // =====================================
            // 🔵 Delete temp contact
            // Only if we created it now
            // =====================================
            if (sr.isSuccess()) {
                delete tempContact;
            }

        } catch (Exception e) {
            throw new AuraHandledException(
                'Email failed: ' + e.getMessage()
            );
        }
    }
}