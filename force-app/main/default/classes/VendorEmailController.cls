/**
 * @description Controller for managing vendor email communications.
 * Handles retrieval of specifications, tasks, and email dispatching.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class VendorEmailController {

    // --- 1. UTILITIES ---

    @AuraEnabled(cacheable=true)
    public static List<ContentVersion> getFilesByOpportunityId(String opportunityId) {
        if (String.isBlank(opportunityId)) {
            return new List<ContentVersion>();
        }
        
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :opportunityId ]) {
            docIds.add(link.ContentDocumentId);
        }

        if (docIds.isEmpty()) {
            return new List<ContentVersion>();
        }

        return [
            SELECT Id, Title, ContentDocumentId, FileType
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE
           
            ORDER BY Title
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getVendorCategories() {
        List<String> categories = new List<String>();
        for (Schema.PicklistEntry entry : Vendor__c.Vendor_Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                categories.add(entry.getValue());
            }
        }
        return categories;
    }

    @AuraEnabled(cacheable=true)
    public static List<Vendor__c> getVendorsByCategory(String category) {
        if (String.isBlank(category)) {
            return new List<Vendor__c>();
        }
        return [
            SELECT Id, Name, Email__c, Vendor_Category__c, Average_Efficiency__c
            FROM Vendor__c
            WHERE Vendor_Category__c = :category
            AND Email__c != NULL
            AND Vendor_Status__c != 'Abscond'
            AND Vendor_Status__c != 'Unavailable'

            ORDER BY Average_Efficiency__c DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<EmailTemplate> getEmailTemplatesByType(String tenderType) {
        String devName = (tenderType == 'Backup') ? 'Backup_Tendor_Invitation' : 'Quatation_Email_Template';
        List<EmailTemplate> templates = [SELECT Id, Name, DeveloperName FROM EmailTemplate WHERE DeveloperName = :devName  LIMIT 1];
        
        if (templates.isEmpty()) {
            throw new AuraHandledException('Template not found: ' + devName);
        }
        return templates;
    }

    // --- 2. DYNAMIC SPECIFICATIONS ---

    @AuraEnabled(cacheable=true)
    public static List<SObject> getSpecificationsByOpportunityAndCategory(String opportunityId, String category) {
        try {
            return new SpecQueryHelper().querySpecs(opportunityId, category);
        } catch (Exception e) {
            return new List<Project_Specification__c>();
        }
    }

    // --- 3. ABSCONDED VENDOR LOGIC ---

    @AuraEnabled(cacheable=true)
    public static AbscondedVendorDetails getAbscondedVendorTasks(String opportunityId, String category) {
        AbscondedVendorDetails details = new AbscondedVendorDetails();
        try {
            List<Vendor_Assignment__c> assigns = [SELECT Id, Vendor_Work_Start_Date__c, Vendor_Work_End_Date__c, Completion__c FROM Vendor_Assignment__c WHERE Vendor_Opportunity__r.Opportunity__c = :opportunityId AND Vendor_Opportunity__r.Vendor_Category__c = :category AND Vendor_Opportunity__r.Vendor_Opportunity_Status__c = 'Abscond'  LIMIT 1];

            if (assigns.isEmpty()) {
                return details;
            }

            Vendor_Assignment__c va = assigns[0];
            details.overallCompletion = (va.Completion__c != null) ? va.Completion__c / 100 : 0;
            details.overallAssignmentStartDate = va.Vendor_Work_Start_Date__c;
            details.overallAssignmentEndDate = va.Vendor_Work_End_Date__c;

            for (Task t : [SELECT Id, Subject, Status FROM Task WHERE WhatId = :va.Id ]) {
                details.tasks.add(new AbscondedTaskWrapper(t));
            }
            return details;
        } catch (Exception e) {
            return details;
        }
    }

    // --- 4. EMAIL SENDING ---

    @AuraEnabled
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static void sendEmailToVendors(String opportunityId, List<String> fileIds, List<String> vendorIds, String category, String tenderType) {
        if (String.isBlank(opportunityId) || vendorIds == null || vendorIds.isEmpty()) {
            throw new AuraHandledException('Required fields missing.');
        }

        EmailSendingContext context = new EmailSendingContext();
        context.opportunityId = opportunityId;
        context.fileIds = fileIds;
        context.vendorIds = vendorIds;
        context.category = category;
        context.tenderType = tenderType;

        new EmailServiceHelper().processAndSendEmails(context);
    }

    // ================= WRAPPER CLASSES =================

    public class AbscondedVendorDetails {
        @AuraEnabled public List<AbscondedTaskWrapper> tasks { get; set; }
        @AuraEnabled public Decimal overallCompletion { get; set; }
        @AuraEnabled public Date overallAssignmentStartDate { get; set; }
        @AuraEnabled public Date overallAssignmentEndDate { get; set; }
        public AbscondedVendorDetails() {
            this.tasks = new List<AbscondedTaskWrapper>();
            this.overallCompletion = 0;
        }
    }

    public class AbscondedTaskWrapper {
        @AuraEnabled public Id taskId { get; set; }
        @AuraEnabled public String taskSubject { get; set; }
        @AuraEnabled public String taskStatus { get; set; }
        public AbscondedTaskWrapper(Task t) {
            this.taskId = t.Id;
            this.taskSubject = t.Subject;
            this.taskStatus = t.Status;
        }
    }

    private class EmailSendingContext {
        public String opportunityId;
        public List<String> fileIds;
        public List<String> vendorIds;
        public String category;
        public String tenderType;
    }

    private class EmailContentWrapper {
        public List<SObject> specs;
        public String specTable;
        public String abscondedTable;
    }

    private class EmailCreationContext {
        public Opportunity opportunity;
        public EmailTemplate template;
        public EmailContentWrapper content;
        public List<Messaging.EmailFileAttachment> attachments;
        public String defaultCategory;
    }

    // ================= HELPERS =================

    private with sharing class SpecQueryHelper {
        public List<SObject> querySpecs(String opportunityId, String category) {
            Schema.FieldSet fs = SObjectType.Project_Specification__c.FieldSets.getMap().get('Vendor_Email_Fields');
            if (fs == null) {
                return new List<Project_Specification__c>();
            }

            List<Schema.FieldSetMember> fields = fs.getFields();
            if (fields.isEmpty()) {
                return new List<Project_Specification__c>();
            }

            String query = 'SELECT Id, Interior_Product__c, Interior_Product__r.Name, Quality__c, Quantity__c, ';
            for (Schema.FieldSetMember f : fields) {
                if (!query.containsIgnoreCase(f.getFieldPath())) {
                    query += f.getFieldPath() + ', ';
                }
            }
            query = query.removeEnd(', ');
            query += ' FROM Project_Specification__c WHERE Opportunity__c = :opportunityId AND Vendor_Category__c = :category ORDER BY CreatedDate ASC';
            return Database.query(query);
        }
    }

    private with sharing class EmailServiceHelper {
        public void processAndSendEmails(EmailSendingContext ctx) {
            String templateDevName = (ctx.tenderType == 'Backup') ? 'Backup_Tendor_Invitation' : 'Quatation_Email_Template';
            EmailTemplate template = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :templateDevName  LIMIT 1];
            
            EmailContentWrapper content = buildContent(ctx);
            
            Opportunity opp = [SELECT Id, Name, Supervisor_User__r.Name, Supervisor_User__r.Email, Supervisor_User__r.Phone, Project_Scope__c FROM Opportunity WHERE Id = :ctx.opportunityId  LIMIT 1];

            List<Messaging.EmailFileAttachment> attachments = buildAttachments(ctx.fileIds, content.specs);
            List<Vendor__c> vendors = [SELECT Id, Name, Email__c, Vendor_Category__c FROM Vendor__c WHERE Id IN :ctx.vendorIds AND Email__c != NULL ];
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            EmailCreationContext creationCtx = new EmailCreationContext();
            creationCtx.opportunity = opp;
            creationCtx.template = template;
            creationCtx.content = content;
            creationCtx.attachments = attachments;
            creationCtx.defaultCategory = ctx.category;

            for (Vendor__c v : vendors) {
                emails.add(createEmail(v, creationCtx));
            }
            
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                throw new AuraHandledException('Error sending emails: ' + e.getMessage());
            }
        }

        private EmailContentWrapper buildContent(EmailSendingContext ctx) {
            EmailContentWrapper wrapper = new EmailContentWrapper();
            if (ctx.tenderType == 'New') {
                wrapper.specs = new SpecQueryHelper().querySpecs(ctx.opportunityId, ctx.category);
                wrapper.specTable = new TableBuilderHelper().buildDynamicSpecificationTable(wrapper.specs);
            } else if (ctx.tenderType == 'Backup') {
                AbscondedVendorDetails ad = VendorEmailController.getAbscondedVendorTasks(ctx.opportunityId, ctx.category);
                wrapper.abscondedTable = new TableBuilderHelper().buildAbscondedTaskTable(ad);
            }
            return wrapper;
        }

        private Messaging.SingleEmailMessage createEmail(Vendor__c v, EmailCreationContext ctx) {
            String cat = (v.Vendor_Category__c != null ? v.Vendor_Category__c : ctx.defaultCategory);
            
            String subject = ctx.template.Subject
                .replace('{{{Vendor_Category__c}}}', cat)
                .replace('{{{Opportunity.Name}}}', (ctx.opportunity.Name != null ? ctx.opportunity.Name : ''))
                .replace('{{{project_scope}}}', (ctx.opportunity.Project_Scope__c != null ? ctx.opportunity.Project_Scope__c : ''));

            String body = ctx.template.HtmlValue
                .replace('{{{Opportunity.Name}}}', (ctx.opportunity.Name != null ? ctx.opportunity.Name : ''))
                .replace('{{{Opportunity.SupervisorName}}}', (ctx.opportunity.Supervisor_User__r?.Name != null ? ctx.opportunity.Supervisor_User__r.Name : ''))
                .replace('{{{Opportunity.SupervisorEmail}}}', (ctx.opportunity.Supervisor_User__r?.Email != null ? ctx.opportunity.Supervisor_User__r.Email : ''))
                .replace('{{{Opportunity.SupervisorPhone}}}', (ctx.opportunity.Supervisor_User__r?.Phone != null ? ctx.opportunity.Supervisor_User__r.Phone : ''))
                .replace('{{{Vendor__c.Name}}}', (v.Name != null ? v.Name : ''))
                .replace('{{{Vendor_Category__c}}}', cat)
                .replace('{{{Vendor__c.Category}}}', cat)
                .replace('{{{Specification_Table}}}', (ctx.content.specTable != null ? ctx.content.specTable : ''))
                .replace('{{{Absconded_Task_Table}}}', (ctx.content.abscondedTable != null ? ctx.content.abscondedTable : ''));

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(UserInfo.getUserId());
            email.setWhatId(ctx.opportunity.Id);
            email.setSaveAsActivity(true);
            email.setToAddresses(new List<String>{ v.Email__c });
            email.setTreatTargetObjectAsRecipient(false);
            email.setSubject(subject);
            email.setHtmlBody(body);
            email.setFileAttachments(ctx.attachments);
            if (ctx.opportunity.Supervisor_User__r?.Name != null) {
                email.setSenderDisplayName(ctx.opportunity.Supervisor_User__r.Name + ' (Project Supervisor)');
            }
            return email;
        }

        private List<Messaging.EmailFileAttachment> buildAttachments(List<String> fileIds, List<SObject> specs) {
            List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
            if (fileIds != null && !fileIds.isEmpty()) {
                for (ContentVersion f : [SELECT Title, VersionData, FileExtension FROM ContentVersion WHERE Id IN :fileIds AND IsLatest = TRUE ]) {
                    Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                    att.setFileName(f.Title + (String.isNotBlank(f.FileExtension) ? '.' + f.FileExtension : ''));
                    att.setBody(f.VersionData);
                    attachments.add(att);
                }
            }
             if (specs != null && !specs.isEmpty()) {
                Set<Id> productIds = new Set<Id>();
                for (SObject s : specs) {
                    Id prodId = (Id) s.get('Interior_Product__c');
                    if (prodId != null) { 
                        productIds.add(prodId); 
                    }
                }
                attachments.addAll(getAttachmentsFromParentIds(productIds));
            }
            return attachments;
        }

        private List<Messaging.EmailFileAttachment> getAttachmentsFromParentIds(Set<Id> parentIds) {
            List<Messaging.EmailFileAttachment> result = new List<Messaging.EmailFileAttachment>();
            if (parentIds.isEmpty()) {
                return result;
            }
            
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink cdl : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :parentIds ]) {
                docIds.add(cdl.ContentDocumentId);
            }
            if (docIds.isEmpty()) {
                return result;
            }
            
            for (ContentVersion cv : [SELECT Title, VersionData, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE ]) {
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                att.setFileName(cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : ''));
                att.setBody(cv.VersionData);
                result.add(att);
            }
            return result;
        }
    }

    /** @description Helper class for HTML Table generation. */
    private with sharing class TableBuilderHelper {

        public String buildDynamicSpecificationTable(List<SObject> records) {
            if (records == null || records.isEmpty()) {
                return ''; // RETURNS EMPTY STRING IF NO DATA
            }
            
            Schema.FieldSet fs = SObjectType.Project_Specification__c.FieldSets.getMap().get('Vendor_Email_Fields');
            if (fs == null) {
                return '';
            }
            
            String table = '<p>Below are the project specifications and requirements. Please review them and submit your best quotation at your earliest convenience.</p><br/>';
            
            table += '<table border="1" style="border-collapse: collapse; width: 100%; font-family: Arial, sans-serif;"><thead style="background-color: #f2f2f2;"><tr>';
            for (Schema.FieldSetMember f : fs.getFields()) {
                if (!f.getFieldPath().containsIgnoreCase('Description')) {
                    table += '<th style="padding: 10px; text-align: left;">' + f.getLabel() + '</th>';
                }
            }
            table += '</tr></thead><tbody>';
            for (SObject row : records) {
                table += '<tr>';
                for (Schema.FieldSetMember f : fs.getFields()) {
                    if (!f.getFieldPath().containsIgnoreCase('Description')) {
                        table += '<td style="padding: 10px;">' + getDeepValue(row, f.getFieldPath()) + '</td>';
                    }
                }
                table += '</tr>';
            }
            return table + '</tbody></table>';
        }

        public String buildAbscondedTaskTable(AbscondedVendorDetails details) {
            if (details == null || (details.tasks.isEmpty() && details.overallCompletion == 0)) {
                return '';
            }
            
            String intro = '<p>For your reference and to assist in your estimation, here are the details from the previous vendor\'s assignment. <b>This information shows the work status at the time of exit.</b></p><br/>';
            
            return intro + buildAbscondedSummary(details) + buildAbscondedRows(details);
        }

        private String buildAbscondedSummary(AbscondedVendorDetails details) {
            String output = '<div style="margin-bottom: 15px; border: 1px solid #ccc; padding: 10px; background-color: #f9f9f9;">';
            if (details.overallCompletion != null) {
                output += '<p><strong>Overall Assignment Completion: </strong>' + (details.overallCompletion * 100).setScale(2) + '%</p>';
            }
            if (details.overallAssignmentStartDate != null) {
                output += '<p><strong>Start Date: </strong>' + details.overallAssignmentStartDate.format() + '</p>';
            }
            if (details.overallAssignmentEndDate != null) {
                output += '<p><strong>End Date: </strong>' + details.overallAssignmentEndDate.format() + '</p>';
            }
            return output + '</div>';
        }

        private String buildAbscondedRows(AbscondedVendorDetails details) {
            if (details.tasks.isEmpty()) {
                return '';
            }
            String output = '<h4 style="margin-top: 15px;">Individual Tasks:</h4><table border="1" style="border-collapse: collapse; width: 100%;"><thead><tr><th style="padding: 8px;">Task</th><th style="padding: 8px;">Status</th></tr></thead><tbody>';
            for (AbscondedTaskWrapper t : details.tasks) {
                output += '<tr><td style="padding: 8px;">' + (t.taskSubject != null ? t.taskSubject : '') + '</td><td style="padding: 8px;">' + (t.taskStatus != null ? t.taskStatus : '') + '</td></tr>';
            }
            return output + '</tbody></table>';
        }

        private String getDeepValue(SObject record, String fieldPath) {
            if (record == null) {
                return '';
            }
            if (!fieldPath.contains('.')) {
                Object val = record.get(fieldPath);
                return (val != null) ? String.valueOf(val) : '';
            }
            List<String> parts = fieldPath.split('\\.');
            SObject currentObj = record;
            for (Integer i = 0; i < parts.size() - 1; i++) {
                currentObj = currentObj.getSObject(parts[i]);
                if (currentObj == null) {
                    return '';
                }
            }
            Object val = currentObj.get(parts[parts.size() - 1]);
            return (val != null) ? String.valueOf(val) : '';
        }
    }
}