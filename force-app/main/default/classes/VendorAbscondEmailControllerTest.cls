@isTest
public class VendorAbscondEmailControllerTest {

    @testSetup
    static void setupData() {
        // 1. Create Email Template (Setup Object)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Use utility to create a template in the current user's folder
            TestDataUtility.createSpecificEmailTemplate(
                'Abscond_Notice_Template', 
                'Abscond Notice', 
                'Subject: Notice'
            );
        }

        // 2. Create Supervisor
        User supervisor = TestDataUtility.createSupervisorUser('SupAbs');

        // 3. Create Prerequisites for Project (Account & Contact)
        // Utility createProject requires a Contact ID
        Account acc = TestDataUtility.createAccount('Test Client Co');
        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com', 'password123');
        client.AccountId = acc.Id;
        update client;

        // 4. Create Project
        Project__c proj = TestDataUtility.createProject('Abscond Project', 50000, client.Id);

        // 5. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Abscond Opportunity', supervisor.Id);
        
        // Update fields required by the controller (Utility doesn't set these by default)
        opp.Lead_Name__c = 'Test Client Name';
        opp.Email__c = 'client@test.com';
        update opp;

        // 6. Create Vendor
        Vendor__c vendor = TestDataUtility.createVendor('Bad Vendor', 'Plumbing & Sanitary', 'vendor@bad.com');

        // 7. Create Vendor Assignment using Utility
        // Utility sets Status to 'In-Progress' by default. We update it to 'Abscond'.
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 0);
        
        va.Opportunity__c = opp.Id;
        va.Vendor__c = vendor.Id;
        va.Supervisor_User__c = supervisor.Id;
        va.Status__c = 'Abscond'; // Key filter for the controller
        update va;
    }

    @isTest
    static void testGetEmailTemplatesByFolder() {
        // 1. Find the folder name where the utility created the template
        EmailTemplate t = [SELECT Folder.Name FROM EmailTemplate WHERE DeveloperName = 'Abscond_Notice_Template' LIMIT 1];
        String folderName = t.Folder.Name;

        Test.startTest();
        // 2. Call Controller
        List<VendorAbscondEmailController.EmailTemplateDTO> results = VendorAbscondEmailController.getEmailTemplatesByFolder(folderName);
        Test.stopTest();

        // 3. Verify
        System.assertNotEquals(0, results.size(), 'Should return templates');
        Boolean found = false;
        for (VendorAbscondEmailController.EmailTemplateDTO dto : results) {
            if (dto.name == 'Abscond Notice') {
                found = true;
                break;
            }
        }
        System.assert(found, 'Should find the specific template created in setup');
    }

    @isTest
    static void testGetVendorsByOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<VendorAbscondEmailController.VendorWrapper> vendors = VendorAbscondEmailController.getVendorsByOpportunity(opp.Id);
        Test.stopTest();

        System.assertEquals(1, vendors.size(), 'Should find 1 absconding vendor');
        System.assertEquals('vendor@bad.com', vendors[0].email, 'Should match vendor email');
    }

    @isTest
    static void testGetClientByOpportunity() {
        Opportunity opp = [SELECT Id, Lead_Name__c FROM Opportunity LIMIT 1];

        Test.startTest();
        VendorAbscondEmailController.LeadWrapper client = VendorAbscondEmailController.getClientByOpportunity(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, client, 'Client wrapper should not be null');
        System.assertEquals('Test Client Name', client.name, 'Client name should match');
        System.assertEquals('client@test.com', client.email, 'Client email should match');
    }

    @isTest
    static void testGetClientByOpportunityMissingEmail() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Email__c = null; // Clear email to test error handling
        update opp;

        Test.startTest();
        VendorAbscondEmailController.LeadWrapper client = VendorAbscondEmailController.getClientByOpportunity(opp.Id);
        Test.stopTest();

        System.assertEquals(null, client, 'Should return null if email is missing');
    }

    @isTest
    static void testSendEmail() {
        Test.startTest();
        VendorAbscondEmailController.sendEmail('test@recipient.com', 'Subject', 'Body Content');
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, invocations, 'One email should be sent');
    }

    @isTest
    static void testSendEmailMissingRecipient() {
        Test.startTest();
        try {
            VendorAbscondEmailController.sendEmail(null, 'Subject', 'Body');
            System.assert(false, 'Should have thrown exception for missing email');
        } catch (AuraHandledException e) {
            System.assert(true, 'Caught expected exception');
        }
        Test.stopTest();
    }
}