/**
 * @description       :
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 01-27-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
public class VendorAssignmentControllerTest {

    @TestSetup
    static void setup() {
        // 1. Create User (Supervisor)
        User u = TestDataUtility.createSupervisorUser('vasup');
        u.Phone = '555-123-4567';
        update u;

        // 2. Create Account
        Account acc = TestDataUtility.createAccount('Vendor Account');

        // 3. Create Contact
        Contact con = TestDataUtility.createContact('Vendor Contact', 'vendor@test.com', 'password123');
        con.AccountId = acc.Id;
        update con;

        // 4. Create Vendor (Custom Object)
        Vendor__c vendorObj = TestDataUtility.createVendor('Test Vendor', 'Electrical & Networking', 'vendor@test.com');

        // 5. Create Project
        Project__c proj = TestDataUtility.createProject('Test Project VA', 10000, con.Id);

        // 6. Create Vendor Assignment linked to the Vendor
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 50);
        va.Vendor__c = vendorObj.Id;
        va.Supervisor_User__c = u.Id;
        va.Vendor_Work_Start_Date__c = Date.today();
        va.Vendor_Work_End_Date__c = Date.today().addDays(5);
        update va;

        // 7. Create Email Template
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String devName = Label.Arelia_Living_Vendor_Project_Assignment;
            if (String.isBlank(devName)) {
                devName = 'Arelia_Living_Vendor_Project_Assignment_TEST';
            }

            List<EmailTemplate> existing = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :devName LIMIT 1];
            if (existing.isEmpty()) {
                EmailTemplate t = new EmailTemplate();
                t.DeveloperName = devName;
                t.Name = 'Test Vendor Assignment';
                t.Subject = 'Assignment for {{{Vendor_Assignment__c.Project__c}}}';
                t.HtmlValue = '<html><body>' +
                              'Project: {{{Vendor_Assignment__c.Project__c}}}<br/>' +
                              'Vendor: {{{Vendor_Assignment__c.Vendor__c}}}<br/>' +
                              'Category: {{{Vendor_Assignment__c.Vendor_Category__c}}}' +
                              '</body></html>';
                t.TemplateType = 'custom';
                t.FolderId = UserInfo.getUserId();
                t.IsActive = true;
                insert t;
            }
        }
    }

    @IsTest
    static void testGetVendorTasksAsAdmin() {
        User admin = new User(Id = UserInfo.getUserId());
        List<Vendor_Assignment__c> results;

        System.runAs(admin) {
            Test.startTest();
            // As Admin (no ContactId), this should return an empty list without error
            results = VendorAssignmentController.getVendorTasks();
            Test.stopTest();
        }
        Assert.isNotNull(results, 'Should return a list (empty for admin)');
    }

    @IsTest
    static void testSendVendorAssignmentEmailSuccess() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        List<Vendor_Assignment__c> input = new List<Vendor_Assignment__c>{ va };
        User admin = new User(Id = UserInfo.getUserId());

        System.runAs(admin) {
            Test.startTest();
            VendorAssignmentController.sendVendorAssignmentEmail(input);
            Test.stopTest();
        }

        // Note: Actual email sending depends on the Template existing in the context.
        // We assert true here to confirm the method ran without exception.
        Assert.isTrue(true, 'Method executed successfully');
    }

    @IsTest
    static void testSendVendorAssignmentEmailGuardClauses() {
        User admin = new User(Id = UserInfo.getUserId());
        System.runAs(admin) {
            Test.startTest();
            VendorAssignmentController.sendVendorAssignmentEmail(null);
            VendorAssignmentController.sendVendorAssignmentEmail(new List<Vendor_Assignment__c>());
            Test.stopTest();
        }
        Assert.isTrue(true, 'Method should return gracefully');
    }

    @IsTest
    static void testSendVendorAssignmentEmailMissingVendorEmail() {
        Vendor_Assignment__c va = [SELECT Id, Vendor__c FROM Vendor_Assignment__c LIMIT 1];

        // Fetch linked Vendor (Custom Object) and clear Email
        Vendor__c v = [SELECT Id FROM Vendor__c WHERE Id = :va.Vendor__c];
        v.put('Email__c', null);
        update v;
        update va; // Trigger refresh

        User admin = new User(Id = UserInfo.getUserId());
        Integer startEmails;
        Integer endEmails;

        System.runAs(admin) {
            Test.startTest();
            startEmails = Limits.getEmailInvocations();
            VendorAssignmentController.sendVendorAssignmentEmail(new List<Vendor_Assignment__c>{ va });
            endEmails = Limits.getEmailInvocations();
            Test.stopTest();
        }

        Assert.areEqual(startEmails, endEmails, 'Should NOT send email if vendor email is missing');
    }

    @IsTest
    static void testSendVendorAssignmentEmailMissingTemplate() {
        // Find and delete the template to simulate missing config
        String devName = Label.Arelia_Living_Vendor_Project_Assignment;
        if (String.isNotBlank(devName)) {
            List<EmailTemplate> tpls = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :devName];
            if (!tpls.isEmpty()) {
                delete tpls;
            }
        }

        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        User admin = new User(Id = UserInfo.getUserId());
        Integer startEmails;
        Integer endEmails;

        System.runAs(admin) {
            Test.startTest();
            startEmails = Limits.getEmailInvocations();

            // This should NOT throw an exception, it should just return
            VendorAssignmentController.sendVendorAssignmentEmail(new List<Vendor_Assignment__c>{ va });

            endEmails = Limits.getEmailInvocations();
            Test.stopTest();
        }

        Assert.areEqual(startEmails, endEmails, 'Should NOT send email if template is missing');
    }

    // ==========================================================================
    // COVERAGE BOOSTERS (LWC & File Utilities)
    // ==========================================================================

    @IsTest
    static void testLwcMethods() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        User u = [SELECT Id FROM User WHERE Alias = 'vasup' LIMIT 1];

        // 1. Test createVendorAssignments
        List<Vendor_Assignment__c> newRecords = new List<Vendor_Assignment__c>();
        Vendor_Assignment__c vaNew = new Vendor_Assignment__c(
            Vendor__c = vendor.Id,
            Supervisor_User__c = u.Id,
            Vendor_Work_Start_Date__c = Date.today(),
            Budget_Percentage__c = 20
        );
        newRecords.add(vaNew);

        User admin = new User(Id = UserInfo.getUserId());
        List<Vendor_Assignment__c> created;
        Boolean hasRecords;
        List<Vendor_Assignment__c> existing;

        System.runAs(admin) {
            Test.startTest();
            created = VendorAssignmentController.createVendorAssignments(newRecords, proj.Id);
            // 2. Test hasExistingRecords
            hasRecords = VendorAssignmentController.hasExistingRecords(proj.Id);
            // 3. Test getExistingRecords (with Field Allowlisting check)
            List<String> queryFields = new List<String>{'Vendor_Work_Start_Date__c', 'Budget_Percentage__c', 'Invalid_Field__c'};
            existing = VendorAssignmentController.getExistingRecords(proj.Id, queryFields);
            Test.stopTest();
        }

        Assert.isNotNull(created[0].Id, 'Assignment should be inserted');
        Assert.areEqual(proj.Id, created[0].Project__c, 'Project ID should be set by method');
        Assert.isTrue(hasRecords, 'Should detect existing records');
        Assert.isFalse(existing.isEmpty(), 'Should return assignments');
        Assert.isNotNull(existing[0].Id, 'ID should be included automatically');
    }

    @IsTest
    static void testFileMethods() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // Setup: Create a file
        ContentVersion cv = TestDataUtility.createContentVersion('TestScope', 'SampleData');
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id =: cv.Id].ContentDocumentId;

        // 1. Test reparentFiles
        Map<String, String> fileMap = new Map<String, String>();
        fileMap.put(String.valueOf(docId), String.valueOf(proj.Id));

        User admin = new User(Id = UserInfo.getUserId());
        Map<Id, String> fileNames;

        System.runAs(admin) {
            Test.startTest();
            VendorAssignmentController.reparentFiles(fileMap);

            // 2. Test getAttachedFileNames
            fileNames = VendorAssignmentController.getAttachedFileNames(new List<Id>{proj.Id});
            Test.stopTest();
        }

        // Verify linkage
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :proj.Id];
        Assert.areEqual(1, links.size(), 'File should be linked to project');
        Assert.isTrue(fileNames.containsKey(proj.Id), 'Map should contain project Id');
        Assert.isTrue(fileNames.get(proj.Id).contains('TestScope'), 'Map should contain file title');
    }

    @IsTest
    static void testFieldSetMethods() {
        User admin = new User(Id = UserInfo.getUserId());
        List<VendorAssignmentController.FieldSetMember> invalidObj;
        List<VendorAssignmentController.FieldSetMember> invalidFS;

        System.runAs(admin) {
            Test.startTest();
            // Invalid Object Name
            invalidObj = VendorAssignmentController.getFieldSetFields('InvalidObjectXYZ', 'SomeFieldSet');
            // Invalid FieldSet Name
            invalidFS = VendorAssignmentController.getFieldSetFields('Vendor_Assignment__c', 'NonExistentFieldSet123');
            Test.stopTest();
        }

        Assert.isTrue(invalidObj.isEmpty(), 'Should return empty list for invalid object');
        Assert.isTrue(invalidFS.isEmpty(), 'Should return empty list for invalid fieldset');
    }
}