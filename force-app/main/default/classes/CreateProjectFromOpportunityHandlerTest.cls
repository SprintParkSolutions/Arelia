@isTest
public class CreateProjectFromOpportunityHandlerTest {

    @testSetup
    static void setup() {
        // 1. Create User as SYSTEM ADMINISTRATOR
        // This ensures full access to custom objects like Vendor_Opportunity__c
        // preventing the "sObject type not supported" QueryException.
        
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User u = new User(
            Alias = 'projHand', 
            Email = 'projHand@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Testing', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = adminProfile.Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'projHand' + DateTime.now().getTime() + '@testorg.com'
        );
        insert u;

        // 2. Create Account
        Account acc = new Account(Name = 'Test Client Company', OwnerId = u.Id);
        insert acc;
        
        // 3. Create Contact
        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com', 'password123');
        client.AccountId = acc.Id;
        client.OwnerId = u.Id; 
        update client;

        // 4. Create Vendor
        TestDataUtility.createVendor('Test Vendor', 'Plumbing & Sanitary', 'vendor@test.com');
    }

    // ==========================================
    // POSITIVE TESTS (Creation & Update)
    // ==========================================

    @isTest
    static void testHandleAfterUpdateCreateProjectSuccess() {
        User u = [SELECT Id FROM User WHERE Alias = 'projHand' LIMIT 1];
        Contact client = [SELECT Id FROM Contact LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        
        // 1. Create Opportunity with AGREEMENT FLAGS TRUE
        Opportunity oldOpp = TestDataUtility.createOpportunity('Test Project Creation', u.Id);
        oldOpp.OwnerId = u.Id; 
        oldOpp.StageName = 'Negotiation';
        oldOpp.Primary_Contact__c = client.Id;
        
        // Set flags BEFORE creating VO to satisfy validation rules
        oldOpp.Client_Agreement_Sent__c = true; 
        oldOpp.Client_Agreement_Signed__c = true;
        oldOpp.All_Vendors_Agreement_Completed__c = true;
        oldOpp.Budget__c = 50000;
        oldOpp.Project_Description__c = 'Test Desc';
        update oldOpp;

        // 2. Create Vendor Opportunity
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(oldOpp.Id, vendor.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = true; 
        vo.Vendor_Agreement_Signed__c = true; 
        update vo;

        ContentVersion cv = TestDataUtility.createContentVersion('Spec Sheet', 'File Content');
        TestDataUtility.linkFileToRecord(cv.Id, oldOpp.Id);

        Opportunity newOpp = oldOpp.clone(true, true, true, true);
        newOpp.StageName = 'Closed Won';
        
        Test.startTest();
        System.runAs(u) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(
                new List<Opportunity>{ newOpp }, 
                new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
            );
        }
        Test.stopTest();

        List<Project__c> projects = [SELECT Id, Name, Budget__c, Supervisor_User__c FROM Project__c WHERE Project_Name__c = :oldOpp.Id];
        Assert.areEqual(1, projects.size(), 'One project should be created');
        Assert.areEqual(50000, projects[0].Budget__c, 'Budget should be mapped');
        Assert.areEqual(u.Id, projects[0].Supervisor_User__c, 'Supervisor should be mapped');

        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :projects[0].Id];
        Assert.areEqual(1, links.size(), 'File should be copied to new project');
    }

    @isTest
    static void testHandleAfterUpdateUpdateProjectSuccess() {
        User u = [SELECT Id FROM User WHERE Alias = 'projHand' LIMIT 1];
        Contact client = [SELECT Id FROM Contact LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        Opportunity oldOpp = TestDataUtility.createOpportunity('Test Project Update', u.Id);
        oldOpp.OwnerId = u.Id; 
        oldOpp.StageName = 'Negotiation';
        oldOpp.Primary_Contact__c = client.Id;
        
        // Set flags
        oldOpp.Client_Agreement_Sent__c = true;
        oldOpp.Client_Agreement_Signed__c = true;
        oldOpp.All_Vendors_Agreement_Completed__c = true;
        update oldOpp;
        
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(oldOpp.Id, vendor.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = true;
        vo.Vendor_Agreement_Signed__c = true;
        update vo;

        Project__c existingProj;
        System.runAs(u) {
            existingProj = TestDataUtility.createProject('Old Name', 1000, client.Id);
            existingProj.Project_Name__c = oldOpp.Id; 
            existingProj.OwnerId = u.Id; 
            update existingProj;
        }

        Opportunity newOpp = oldOpp.clone(true, true, true, true);
        newOpp.StageName = 'Closed Won';
        newOpp.Budget__c = 99999; 

        Test.startTest();
        System.runAs(u) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(
                new List<Opportunity>{ newOpp }, 
                new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
            );
        }
        Test.stopTest();

        Project__c updatedProj = [SELECT Budget__c FROM Project__c WHERE Id = :existingProj.Id];
        Assert.areEqual(99999, updatedProj.Budget__c, 'Existing project budget should be updated');
    }

    // ==========================================
    // VALIDATION (GATE) TESTS
    // ==========================================

    @isTest
    static void testValidationClientAgreementMissing() {
        User u = [SELECT Id FROM User WHERE Alias = 'projHand' LIMIT 1];
        
        Opportunity oldOpp = TestDataUtility.createOpportunity('Gate Test', u.Id);
        oldOpp.OwnerId = u.Id; 
        oldOpp.StageName = 'Negotiation';
        oldOpp.Client_Agreement_Signed__c = false; // FAIL CONDITION
        oldOpp.All_Vendors_Agreement_Completed__c = true;
        update oldOpp;

        Opportunity newOpp = oldOpp.clone(true, true, true, true);
        newOpp.StageName = 'Closed Won';

        Test.startTest();
        System.runAs(u) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(
                new List<Opportunity>{ newOpp }, 
                new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
            );
        }
        Test.stopTest();
        
        Assert.isTrue(newOpp.hasErrors(), 'Should have errors');
        Assert.isTrue(newOpp.getErrors()[0].getMessage().contains('Client Agreement'), 'Error should mention Client Agreement');
    }

    @isTest
    static void testValidationVendorAgreementMissing() {
        User u = [SELECT Id FROM User WHERE Alias = 'projHand' LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        
        Opportunity oldOpp = TestDataUtility.createOpportunity('Vendor Gate Test', u.Id);
        oldOpp.OwnerId = u.Id; 
        oldOpp.StageName = 'Negotiation';
        
        // Must be TRUE to create VO
        oldOpp.Client_Agreement_Sent__c = true; 
        oldOpp.Client_Agreement_Signed__c = true;
        oldOpp.All_Vendors_Agreement_Completed__c = true;
        update oldOpp;

        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(oldOpp.Id, vendor.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = true;
        vo.Vendor_Agreement_Signed__c = false; // FAIL CONDITION (Not signed)
        update vo;

        Opportunity newOpp = oldOpp.clone(true, true, true, true);
        newOpp.StageName = 'Closed Won';

        Test.startTest();
        System.runAs(u) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(
                new List<Opportunity>{ newOpp }, 
                new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
            );
        }
        Test.stopTest();

        Assert.isTrue(newOpp.hasErrors(), 'Should have errors');
        Assert.isTrue(newOpp.getErrors()[0].getMessage().contains('have not signed'), 'Error should mention vendor signature');
    }

    @isTest
    static void testValidationAllVendorsFlagMissing() {
        User u = [SELECT Id FROM User WHERE Alias = 'projHand' LIMIT 1];

        Opportunity oldOpp = TestDataUtility.createOpportunity('Flag Test', u.Id);
        oldOpp.OwnerId = u.Id; 
        oldOpp.StageName = 'Negotiation';
        
        oldOpp.Client_Agreement_Sent__c = true;
        oldOpp.Client_Agreement_Signed__c = true;
        oldOpp.All_Vendors_Agreement_Completed__c = false; // FAIL CONDITION
        update oldOpp;

        Opportunity newOpp = oldOpp.clone(true, true, true, true);
        newOpp.StageName = 'Closed Won';

        Test.startTest();
        System.runAs(u) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(
                new List<Opportunity>{ newOpp }, 
                new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
            );
        }
        Test.stopTest();

        Assert.isTrue(newOpp.hasErrors(), 'Should have errors');
        Assert.isTrue(newOpp.getErrors()[0].getMessage().contains('All Vendors Agreement not completed'), 'Error should mention completion flag');
    }

    // ==========================================
    // SPECIAL LOGIC TESTS
    // ==========================================

    @isTest
    static void testRevisitLogicMapping() {
        User u = [SELECT Id FROM User WHERE Alias = 'projHand' LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        
        Opportunity oldOpp = TestDataUtility.createOpportunity('Re-Visit Test', u.Id);
        oldOpp.OwnerId = u.Id;
        oldOpp.StageName = 'Negotiation';
        
        oldOpp.Client_Agreement_Sent__c = true;
        oldOpp.Client_Agreement_Signed__c = true;
        oldOpp.All_Vendors_Agreement_Completed__c = true;
        update oldOpp;
        
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(oldOpp.Id, vendor.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = true;
        vo.Vendor_Agreement_Signed__c = true;
        update vo;

        Opportunity newOpp = oldOpp.clone(true, true, true, true);
        newOpp.StageName = 'Closed Won';
        newOpp.Appointment_Status__c = 'Re-Visit';
        newOpp.Re_Visit_Appointmnet_Confirmation__c = true; 
        newOpp.Re_Visit_Site_Supervisor_Completion_Date__c = Date.today().addDays(10);
        newOpp.Re_Visit_Site_Supervisor_Estimate_Budget__c = 5000;

        Test.startTest();
        System.runAs(u) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(
                new List<Opportunity>{ newOpp }, 
                new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
            );
        }
        Test.stopTest();

        Project__c p = [SELECT Supervisor_Estimated_Budget__c FROM Project__c WHERE Project_Name__c = :oldOpp.Id];
        Assert.areEqual(5000, p.Supervisor_Estimated_Budget__c, 'Budget should map from Re-Visit field');
    }

    @isTest
    static void testIgnoreIrrelevantChanges() {
        User u = [SELECT Id FROM User WHERE Alias = 'projHand' LIMIT 1];

        Opportunity oldOpp = TestDataUtility.createOpportunity('No Change Test', u.Id);
        oldOpp.OwnerId = u.Id; 
        oldOpp.StageName = 'Negotiation';
        update oldOpp;

        Opportunity newOpp = oldOpp.clone(true, true, true, true);
        newOpp.StageName = 'Prospecting';

        Test.startTest();
        System.runAs(u) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(
                new List<Opportunity>{ newOpp }, 
                new Map<Id, Opportunity>{ oldOpp.Id => oldOpp }
            );
        }
        Test.stopTest();

        Integer projCount = [SELECT COUNT() FROM Project__c WHERE Project_Name__c = :oldOpp.Id];
        Assert.areEqual(0, projCount, 'No project should be created for non-Won status change');
    }
}