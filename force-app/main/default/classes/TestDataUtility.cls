/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-11-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
@SuppressWarnings('PMD.ExcessivePublicCount, PMD.ExcessiveParameterList, PMD.ExcessiveParameterList')
public class TestDataUtility {

    // 1. Create User
    public static User createSupervisorUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, 
            Email = alias + '@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Testing', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = alias + DateTime.now().getTime() + '@testorg.com'
        );
        insert u;
        return u;
    }

    // 2. Create Project
    public static Project__c createProject(String name, Decimal projectBudget, Id contactId) {
        Project__c proj = new Project__c(
            Name = name, 
            Status__c = 'In Progress',
            Project_Status__c='Active',
            Supervisor_Estimated_Budget__c = projectBudget,
            Client__c = contactId
        );
        insert proj;
        return proj;
    }

    // 3. Create Opportunity
    public static Opportunity createOpportunity(String name, Id supervisorId) {
        Opportunity opp = new Opportunity(
            Name = name,
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            Supervisor_User__c = supervisorId,
            Project_Scope__c = 'Dining Hall'
        );
        insert opp;
        return opp;
    }

    // Create Task
    public static Task createTask(String status, Id whatId, Decimal assignedPercentage) {
        Task taskDetails = new Task(
            Subject = 'New task Created',
            Start_Date__c = System.today(),
            ActivityDate = Date.today().addDays(30),
            Status = status,
            WhatId = whatId,
            Assigned_Percentage__c = assignedPercentage,
            OwnerId = UserInfo.getUserId()
        );
        insert taskDetails;
        return taskDetails;
    }

    // 4. Create Vendor
    public static Vendor__c createVendor(String name, String category, String email) {
        Vendor__c vendor = new Vendor__c(
            Name = name,
            Email__c = email,
            Vendor_Category__c = category,
            Vendor_Status__c = 'Available',
            Average_Efficiency__c = 95.5
        );
        insert vendor;
        return vendor;
    }

    // 5. Create File (ContentVersion)
    public static ContentVersion createContentVersion(String title, String fileContent) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf(fileContent),
            IsMajorVersion = true
        );
        insert cv;
        return cv;
    }

    // 6. Link File to Record (ContentDocumentLink)
    public static ContentDocumentLink linkFileToRecord(Id contentVersionId, Id linkedEntityId) {
        // Handle case where contentVersionId is already a ContentDocumentId vs ContentVersionId
        Id conDocId;
        String keyPrefix = String.valueOf(contentVersionId).substring(0,3);
        
        if (keyPrefix == '068') { // ContentVersion
             conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId].ContentDocumentId;
        } else { // ContentDocument
             conDocId = contentVersionId;
        }
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = linkedEntityId,
            ContentDocumentId = conDocId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
        return cdl;
    }

    // 7. Create Email Templates (Generic)
    public static void createEmailTemplates() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = new List<EmailTemplate>();
            
            templates.add(new EmailTemplate(
                DeveloperName = 'Backup_Tendor_Invitation',
                Name = 'Backup Tender Invitation',
                Subject = 'Tender: {{{project_scope}}}',
                HtmlValue = '<html><body>Test Email Backup {{{Vendor_Category__c}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            ));

            templates.add(new EmailTemplate(
                DeveloperName = 'Quatation_Email_Template',
                Name = 'Quotation Email Template',
                Subject = 'New Tender: {{{project_scope}}}',
                HtmlValue = '<html><body>Test Email New {{{Vendor_Category__c}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            ));
            
            insert templates;
        }
    }

    // Wrapper class to solve "Excessive Parameter List"
    public class AbscondDataParams {
        public Id oppId;
        public Id vendorId;
        public Id supervisorId;
        public Id projId;
        public String voStatus;
        public Decimal completion;
    }

    // 8. Complex Data: Abscond Data
    public static void createAbscondData(AbscondDataParams params) {
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = params.oppId,
            Vendor__c = params.vendorId,
            Vendor_Opportunity_Status__c = params.voStatus
        );
        insert vo;

        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id,
            Opportunity__c = params.oppId,
            Supervisor_User__c = params.supervisorId,
            Project__c = params.projId,
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today().addDays(5),
            Completion__c = params.completion
        );
        insert va;

        Task t = new Task(
            Subject = 'Test Task',
            Status = 'Not Started',
            WhatId = va.Id
        );
        insert t;
    }

    // 9. Complex Data: Spec Data
    public static void createSpecData(Id oppId, String category, String productName) {
        Interior_Product__c product = new Interior_Product__c(Name = productName);
        insert product;

        ContentVersion cv = createContentVersion('Spec File ' + productName, 'Test File Content');
        linkFileToRecord(cv.Id, product.Id);

        Project_Specification__c spec = new Project_Specification__c(
            Opportunity__c = oppId,
            Interior_Product__c = product.Id,
            Vendor_Category__c = category
        );
        insert spec;
    }

    // 10. Create Payment Term
    public static Payment_Term__c createPaymentTerm(Id parentId, String label, Decimal percentage) {
        Payment_Term__c term = new Payment_Term__c(
            Term_Label__c = label,
            Percentage__c = percentage,
            Due_Date__c = Date.today().addDays(15),
            Name = label
        );

        String sObjName = parentId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            term.Opportunity__c = parentId;
        } else if (sObjName == 'Project__c') {
            term.Project__c = parentId;
        }

        insert term;
        return term;
    }

    // 11. Create Lead
    public static Lead createLead(String lastName) {
        Lead l = new Lead(
            LastName = lastName, 
            Company = 'Test Company', 
            Status = 'Open - Not Contacted'
        );
        insert l;
        return l;
    }

    // 12. Create Site Visit Report
    public static Site_Visit_Report__c createSiteVisitReport(Id parentId, String rtName) {
        Id rtId = Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByName()
            .get(rtName)
            .getRecordTypeId();

        Site_Visit_Report__c svr = new Site_Visit_Report__c(
            RecordTypeId = rtId,
            Wizard_Step__c = 1,
            Total_Estimated_Cost__c = 1000
        );

        String sObj = parentId.getSObjectType().getDescribe().getName();
        if (sObj == 'Lead') {
            svr.Lead__c = parentId;
        } else if (sObj == 'Opportunity') {
            svr.Opportunity__c = parentId;
        }
        
        insert svr;
        return svr;
    }

    // 13. Create Vendor Opportunity
    public static Vendor_Opportunity__c createVendorOpportunity(Id oppId, Id vendorId, String status) {
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = oppId,
            Vendor__c = vendorId,
            Vendor_Opportunity_Status__c = status
        );
        insert vo;
        return vo;
    }

    // 14. Create Custom Quotation
    public static Quotation__c createQuotation(Id oppId, String name) {
        Quotation__c q = new Quotation__c(
            Name = name,
            Opportunity__c = oppId 
        );
        insert q;
        return q;
    }

    // 15. Create Vendor Assignment
    public static Vendor_Assignment__c createVendorAssignment(Id projectId, Decimal assignedPercentage) {
        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Project__c = projectId,
            Status__c='In-Progress',
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today().addDays(10),
            Budget_Percentage__c = assignedPercentage
        );
        insert va;
        return va;
    }
    
    // 16. Create Account
    public static Account createAccount(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }
    
    // 17. Create Contact
    public static Contact createContact(String lastName, String email, String password) {
        Contact c = new Contact(
            LastName = lastName,
            Email = email,
            Password__c = password
        );
        insert c;
        return c;
    }

    public class AppointmentLeadParams {
        public Id supervisorId;
        public String status;
        public Date apptDate;
        public String slot;
    }

    // 18. Create Appointment Lead
    public static Lead createAppointmentLead(AppointmentLeadParams params) {
        String uniqueEmail = 'testlead' + DateTime.now().getTime() + '@example.com';
        
        Lead l = new Lead(
            LastName = 'Appt Lead ' + DateTime.now().getTime(),
            Company = 'Test Company',
            Status = 'Open - Not Contacted',
            Supervisor_User__c = params.supervisorId,
            Appointment_Status__c = params.status,
            Appointment_Date__c = params.apptDate,
            Appointment_Time_Slots__c = params.slot,
            Email = uniqueEmail
        );

        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true; 
        dml.DuplicateRuleHeader.runAsCurrentUser = true;
        l.setOptions(dml);

        insert l;
        return l;
    }

    public class AppointmentOppParams {
        public Id supervisorId;
        public String status; 
        public Date apptDate; 
        public String slot;   
        public Id contactId;  
    }

    // 19. Create Appointment Opportunity
    public static Opportunity createAppointmentOpportunity(AppointmentOppParams params) {
        Opportunity opp = new Opportunity(
            Name = 'Appt Opp ' + DateTime.now().getTime(),
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Supervisor_User__c = params.supervisorId,
            Re_Visit_Site_Appointment_Status__c = params.status,
            Re_Visit_Appointment_Date__c = params.apptDate,
            Re_Visit_Appointment_Time_Slots__c = params.slot,
            Primary_Contact__c = params.contactId
        );
        insert opp;
        return opp;
    }

    // 20. Create Specific Email Template (Default Body)
    public static EmailTemplate createSpecificEmailTemplate(String devName, String name, String subject) {
        return createSpecificEmailTemplate(devName, name, subject, '<html><body>Test Content for ' + name + '</body></html>');
    }

    // 20b. Create Specific Email Template (Custom Body) - NEW
    public static EmailTemplate createSpecificEmailTemplate(String devName, String name, String subject, String htmlBody) {
        EmailTemplate et = new EmailTemplate(
            DeveloperName = devName,
            Name = name,
            Subject = subject,
            HtmlValue = htmlBody,
            TemplateType = 'custom',
            FolderId = UserInfo.getUserId(),
            IsActive = true
        );
        insert et;
        return et;
    }

    // 21. Create User Role
    public static UserRole createUserRole(String name) {
        UserRole r = new UserRole(DeveloperName = name.replaceAll('\\s+','_'), Name = name);
        insert r;
        return r;
    }

    // 22. Create User with Role
    public static User createUserWithRole(String alias, Id roleId) {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, 
            Email = alias + '@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Testing', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = p.Id, 
            UserRoleId = roleId, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = alias + DateTime.now().getTime() + '@testorg.com'
        );
        insert u;
        return u;
    }

    // 23. Create Architecture Design - NEW
    public static Architecture_Design__c createArchitectureDesign(Id parentId, String fileId, String status) {
        Architecture_Design__c ad = new Architecture_Design__c(
            Related_File_Id__c = fileId,
            Status__c = status,
            Secure_Token__c = UUID.randomUUID().toString() // Generate default token
        );
        
        // Dynamic parent link
        String sObjName = parentId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            ad.Opportunity__c = parentId;
        } else if (sObjName == 'Project__c') {
            ad.Project__c = parentId;
        }
        
        insert ad;
        return ad;
    }

    // 24. Create Interior Product - CORRECTED
    public static Interior_Product__c createInteriorProduct(String name, String roomType, String category, Decimal price) {
        Interior_Product__c prod = new Interior_Product__c(
            Name = name,
            Room_Type__c = roomType,
            Product_Category__c = category,
            Unit_Price__c = price,
            Image_File_Name__c = 'test_image.jpg' // Dummy value for field coverage
        );
        insert prod;
        return prod;
    }
    
    // 25. Create WhatsApp Chat  ✅ NEW
    // ----------------------------
    public static WhatsApp_Chat__c createWhatsAppChat(Id leadId, Id opportunityId, Id projectId, String lastFrom, String lastTo) {
        WhatsApp_Chat__c chat = new WhatsApp_Chat__c(
            Lead__c = leadId,
            Opportunity__c = opportunityId,
            Project__c = projectId,
            Last_From__c = lastFrom,
            Last_To__c = lastTo,
            Message_Count__c = 0,
            Last_Status__c = 'sent',
            Last_Message_Time__c = System.now(),
            Transcript_NDJSON__c = ''
        );
        insert chat;
        return chat;
    }

    // 26. Create Proforma Invoice (NEW ADDITION)
    public static Proforma_Invoice__c createProformaInvoice(Id oppId) {
        Proforma_Invoice__c pi = new Proforma_Invoice__c(
            Opportunity__c = oppId
        );
        insert pi;
        return pi;
    }
}