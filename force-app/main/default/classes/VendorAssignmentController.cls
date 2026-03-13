@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class VendorAssignmentController {
    
    private static final String EMAIL_TEMPLATE_DEVELOPER_NAME = Label.Arelia_Living_Vendor_Project_Assignment;

    @AuraEnabled(cacheable=true)
    public static List<Vendor_Assignment__c> getVendorTasks() {
        List<User> currentUser = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Id contactId = (currentUser.isEmpty()) ? null : currentUser[0].ContactId;

        return [SELECT Id, Name, Vendor_Work_End_Date__c, Vendor_Work_Start_Date__c,
                Completion__c, Project__c, Supervisor_User__c
                FROM Vendor_Assignment__c WHERE Vendor__c = :contactId
                ];
    }

    public static void sendVendorAssignmentEmail(List<Vendor_Assignment__c> assignments) {
        if (assignments == null || assignments.isEmpty()) { 
            return; 
        }

        Set<Id> assignmentIds = new Map<Id, Vendor_Assignment__c>(assignments).keySet();
        List<Vendor_Assignment__c> vendorAssignments = fetchVendorAssignments(assignmentIds);
        EmailTemplate template = loadEmailTemplate();
        
        if (template == null) { 
            return; 
        }

        List<Messaging.SingleEmailMessage> emails = generateEmails(vendorAssignments, template);

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                throw new AuraHandledException('Email send failed: ' + e.getMessage());
            }
        }
    }

    private static List<Messaging.SingleEmailMessage> generateEmails(List<Vendor_Assignment__c> vendorAssignments, EmailTemplate template) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Vendor_Assignment__c va : vendorAssignments) {
            if (va.Vendor__r != null && String.isNotBlank(va.Vendor__r.Email__c)) {
                Messaging.SingleEmailMessage email = buildEmail(template, va);
                if (email != null) { 
                    emails.add(email); 
                }
            }
        }
        return emails;
    }

    private static List<Vendor_Assignment__c> fetchVendorAssignments(Set<Id> assignmentIds) {
        return [
            SELECT Id, Vendor_Work_Start_Date__c, Vendor_Work_End_Date__c, Vendor_Category__c,
                   Vendor__r.Email__c, Vendor__r.Name,
                   Project__r.Name,
                   Supervisor_User__r.Name, Supervisor_User__r.Email, Supervisor_User__r.Phone
            FROM Vendor_Assignment__c
            WHERE Id IN :assignmentIds
           
        ];
    }

    private static EmailTemplate loadEmailTemplate() {
        try {
            return [SELECT Id, Subject, HtmlValue, Body
                    FROM EmailTemplate
                    WHERE DeveloperName = :EMAIL_TEMPLATE_DEVELOPER_NAME
                     LIMIT 1];
        } catch (Exception e) {
            return null; 
        }
    }

    private static Messaging.SingleEmailMessage buildEmail(EmailTemplate template, Vendor_Assignment__c va) {
        String rawBody = String.isNotBlank(template.HtmlValue) ? template.HtmlValue : template.Body;
        if (rawBody == null) { 
            rawBody = ''; 
        }

        String htmlBody = replaceMergeFields(rawBody, va);
        
        String subject = (template.Subject != null ? template.Subject : '')
            .replace('{{{Vendor_Assignment__c.Project__c}}}', getValue(va.Project__r?.Name));

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ va.Vendor__r.Email__c });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setWhatId(va.Id);
        email.setSaveAsActivity(false);

        Id orgWideEmailId = getOrgWideEmailAddressId();
        if (orgWideEmailId != null) { 
            email.setOrgWideEmailAddressId(orgWideEmailId); 
        }

        return email;
    }

    private static String replaceMergeFields(String body, Vendor_Assignment__c va) {
        return body
            .replace('{{{Vendor_Assignment__c.Project__c}}}', getValue(va.Project__r?.Name))
            .replace('{{{Vendor_Assignment__c.Vendor__c}}}', getValue(va.Vendor__r?.Name))
            .replace('{{{Vendor_Assignment__c.Vendor_Work_Start_Date__c}}}', formatDate(va.Vendor_Work_Start_Date__c))
            .replace('{{{Vendor_Assignment__c.Vendor_Work_End_Date__c}}}', formatDate(va.Vendor_Work_End_Date__c))
            .replace('{{{Vendor_Assignment__c.Supervisor_User__c}}}', getValue(va.Supervisor_User__r?.Name))
            .replace('{{{Vendor_Assignment__c.Supervisor_Email}}}', getValue(va.Supervisor_User__r?.Email))
            .replace('{{{Vendor_Assignment__c.Supervisor_Phone}}}', getValue(va.Supervisor_User__r?.Phone))
            .replace('{{{Vendor_Assignment__c.Vendor_Category__c}}}', getValue(va.Vendor_Category__c));
    }

    private static String getValue(String val) { 
        return val != null ? val : ''; 
    }
    
    private static String formatDate(Date d) { 
        return d != null ? d.format() : ''; 
    }

    private static Id getOrgWideEmailAddressId() {
        if (String.isBlank(Label.Arelia_OWD)) { 
            return null; 
        }
        
        List<OrgWideEmailAddress> owea = [
            SELECT Id FROM OrgWideEmailAddress 
            WHERE Address =: Label.Arelia_OWD 
             LIMIT 1];
        return owea.isEmpty() ? null : owea[0].Id;
    }

    public class FieldSetMember {
        @AuraEnabled public String label;
        @AuraEnabled public String fieldPath;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean isEditable; 
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldSetMember> getFieldSetFields(String objectName, String fieldSetName) {
        List<FieldSetMember> fieldList = new List<FieldSetMember>();
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
        
        if (sObjectType == null) { 
            return fieldList; 
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Schema.FieldSet fieldSet = describeResult.fieldSets.getMap().get(fieldSetName);

        if (fieldSet != null) {
            for (Schema.FieldSetMember f : fieldSet.getFields()) {
                FieldSetMember wrapper = new FieldSetMember();
                wrapper.label = f.getLabel();
                wrapper.fieldPath = f.getFieldPath();
                wrapper.required = f.getRequired() || f.getDbRequired();
                fieldList.add(wrapper);
            }
        }
        return fieldList;
    }

    @AuraEnabled
    public static Boolean hasExistingRecords(Id projectId) {
        return [SELECT Count() FROM Vendor_Assignment__c WHERE Project__c = :projectId ] > 0;
    }

    @AuraEnabled
    public static List<Vendor_Assignment__c> createVendorAssignments(List<Vendor_Assignment__c> records, Id projectId) {
        for(Vendor_Assignment__c va : records) {
            va.Project__c = projectId; 
        }
        
        if (Schema.sObjectType.Vendor_Assignment__c.isCreateable()) {
            insert records;
        } else {
            throw new AuraHandledException('Insufficient permissions to create Vendor Assignment records.');
        }
        return records;
    }

    @AuraEnabled
    @SuppressWarnings('PMD.ApexSOQLInjection') // Suppressing because we use Schema Whitelisting (fieldMap check) and Bind Variables
    public static List<Vendor_Assignment__c> getExistingRecords(Id projectId, List<String> queryFields) {
        if (!queryFields.contains('Id')) {
            queryFields.add('Id');
        }
        
        // 1. Establish the Whitelist (Allowlist)
        Map<String, SObjectField> fieldMap = Schema.SObjectType.Vendor_Assignment__c.fields.getMap();
        List<String> safeFields = new List<String>();

        // 2. Filter inputs against the Whitelist
        for (String field : queryFields) {
            // Check if the field exists in Schema AND is accessible to the user
            if (fieldMap.containsKey(field) && fieldMap.get(field).getDescribe().isAccessible()) {
                // escapeSingleQuotes is technically redundant here because we checked the map keys, 
                // but it's good practice to leave it for PMD/Security reviews.
                safeFields.add(String.escapeSingleQuotes(field));
            }
        }

        if (safeFields.isEmpty()) {
            safeFields.add('Id');
        }

        // 3. Construct Query
        // Note: Project__c uses a Bind Variable (:projectId), which is secure.
        String query = 'SELECT ' + String.join(safeFields, ',') + 
                       ' FROM Vendor_Assignment__c WHERE Project__c = :projectId';
        
        return Database.query(query);
    }
    @AuraEnabled
    public static void reparentFiles(Map<String, String> fileMap) {
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        
        for(String docId : fileMap.keySet()) {
            ContentDocumentLink newLink = new ContentDocumentLink();
            newLink.ContentDocumentId = docId;
            newLink.LinkedEntityId = fileMap.get(docId); 
            newLink.ShareType = 'V'; 
            linksToInsert.add(newLink);
        }
        
        if (!linksToInsert.isEmpty()) {
            if (Schema.sObjectType.ContentDocumentLink.isCreateable()) {
                insert linksToInsert;
            } else {
                throw new AuraHandledException('Insufficient permissions to link files.');
            }
        }
    }

    @AuraEnabled
    public static Map<Id, String> getAttachedFileNames(List<Id> parentIds) {
        Map<Id, String> fileMap = new Map<Id, String>();
        
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId IN :parentIds 
           
            ORDER BY SystemModstamp DESC
        ];

        for(ContentDocumentLink link : links) {
            if(!fileMap.containsKey(link.LinkedEntityId)) {
                fileMap.put(link.LinkedEntityId, link.ContentDocument.Title + '.' + link.ContentDocument.FileExtension);
            }
        }
        return fileMap;
    }
}