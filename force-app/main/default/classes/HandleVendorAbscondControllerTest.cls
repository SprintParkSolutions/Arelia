@isTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessivePublicCount')
public class HandleVendorAbscondControllerTest {

    @testSetup
    static void setup() {
        // 1. Create Supervisor
        User u = TestDataUtility.createSupervisorUser('abscUser');

        // 2. Create Business Account
        Account acc = TestDataUtility.createAccount('Abscond Client Co');
        acc.Email__c = 'client@test.com'; 
        update acc;

        // 3. Create Contact
        Contact client = TestDataUtility.createContact('Test Client Name', 'client@test.com', 'password123');
        client.AccountId = acc.Id;
        update client;

        // 4. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Abscond Opp', u.Id);
        opp.AccountId = acc.Id;
        opp.Email__c = 'oppclient@test.com'; 
        opp.Lead_Name__c = 'Test Client Name';
        
        // FIX: Set Agreement flags safely to allow VO creation
        try {
            opp.put('Client_Agreement_Sent__c', true);
            opp.put('Client_Agreement_Signed__c', true);
        } catch(Exception e) {
            System.debug('Field write failed (optional fields): ' + e.getMessage());
        }
        update opp;

        // 5. Create Vendor
        Vendor__c v = TestDataUtility.createVendor('Runaway Vendor', 'Electrical & Networking', 'vendor@runaway.com');
        
        // 6. Create Vendor Opportunity
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id,
            Vendor__c = v.Id,
            Vendor_Opportunity_Status__c = 'Active',
            Vendor_Agreement_Signed__c = true 
        );
        insert vo;

        // 7. Create Project
        Project__c proj = TestDataUtility.createProject('Abscond Project', 50000, client.Id);

        // 8. Create Vendor Assignment
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 0); 
        va.Opportunity__c = opp.Id;
        va.Vendor_Opportunity__c = vo.Id;
        va.Vendor__c = v.Id;
        va.Supervisor_User__c = u.Id;
        va.Status__c = 'Abscond'; 
        update va;

        // 9. Create Template
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate('Vendor_Abscond_Template', 'Abscond Notice', 'Urgent');
        }
    }

    // -------------------------------------------------------------------
    // ✅ 1. DTO & Data Retrieval Tests
    // -------------------------------------------------------------------

    @isTest
    static void testGetEmailTemplatesByFolder() {
        Test.startTest();
        List<HandleVendorAbscondController.EmailTemplateDTO> results = 
            HandleVendorAbscondController.getEmailTemplatesByFolder();
        Test.stopTest();
        
        Assert.isNotNull(results, 'Should return a non-null list of templates');
    }

    @isTest
    static void testDTOStructure() {
        Test.startTest();
        HandleVendorAbscondController.EmailTemplateDTO tplDto = new HandleVendorAbscondController.EmailTemplateDTO();
        tplDto.id = UserInfo.getUserId();
        tplDto.name = 'Test';
        tplDto.developerName = 'Test_Dev';
        tplDto.folderName = 'Test_Folder';

        HandleVendorAbscondController.VendorWrapper venWrap = new HandleVendorAbscondController.VendorWrapper();
        venWrap.id = UserInfo.getUserId();
        venWrap.name = 'Vendor';
        venWrap.email = 'v@v.com';

        HandleVendorAbscondController.VendorClientDTO clientDto = new HandleVendorAbscondController.VendorClientDTO();
        clientDto.clientEmail = 'c@c.com';
        clientDto.clientName = 'Client';
        clientDto.vendors = new List<HandleVendorAbscondController.VendorWrapper>{ venWrap };
        Test.stopTest();

        Assert.areEqual('Test', tplDto.name, 'DTO Name should match input');
        Assert.areEqual('Vendor', clientDto.vendors[0].name, 'Vendor Name in DTO should match input');
    }

    @isTest
    static void testGetAbscondVendorsAndClientFullData() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.areEqual('oppclient@test.com', result.clientEmail, 'Should use Opp email');
        Assert.areEqual('Test Client Name', result.clientName, 'Should use Opp Lead Name');
        Assert.areEqual(1, result.vendors.size(), 'Should find 1 vendor');
        Assert.areEqual('Runaway Vendor', result.vendors[0].name, 'Vendor name should match');
    }

    @isTest
    static void testGetAbscondVendorsAndClientAccountFallback() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Email__c = null;     
        opp.Lead_Name__c = null; 
        update opp;

        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.areEqual('client@test.com', result.clientEmail, 'Should fallback to Account Email');
        Assert.areEqual('Abscond Client Co', result.clientName, 'Should fallback to Account Name');
    }

    @isTest
    static void testGetAbscondVendorsAndClientPersonEmailFallback() {
        Id personAccountRTId;
        try {
            personAccountRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
        } catch (Exception e) {
            System.debug('Person Account not enabled. Skipping test.');
            return;
        }

        Account pa = new Account(
            RecordTypeId = personAccountRTId,
            LastName = 'PersonClient',
            PersonEmail = 'person@test.com',
            Email__c = null
        );
        insert pa;

        Opportunity opp = new Opportunity(
            Name = 'Person Opp',
            StageName = 'Proposal',
            CloseDate = Date.today(),
            AccountId = pa.Id
        );
        
        // FIX: Satisfy validation (EmptyCatchBlock addressed)
        try {
            opp.put('Client_Agreement_Sent__c', true);
            opp.put('Client_Agreement_Signed__c', true);
        } catch(Exception e) {
            System.debug('Field write failed in fallback test: ' + e.getMessage());
        }
        
        insert opp;

        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.areEqual('person@test.com', result.clientEmail, 'Should retrieve PersonEmail from Account');
    }

    // -------------------------------------------------------------------
    // ✅ 2. Send Email Tests
    // -------------------------------------------------------------------

    @isTest
    static void testSendEmailVendorLogicMultiple() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];

        List<String> recipients = new List<String>{'v1@test.com', 'v2@test.com'};
        List<Id> assignmentIds = new List<Id>{va.Id, va.Id};

        Test.startTest();
        String result = HandleVendorAbscondController.sendEmail(
            tpl.Id, 
            recipients, 
            opp.Id, 
            'Vendor', 
            assignmentIds
        );
        Test.stopTest();

        Assert.areEqual('SUCCESS', result, 'Vendor email send should return SUCCESS');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE LastName = 'TempRecipient'], 'Dummy contact should be deleted');
    }

    @isTest
    static void testSendEmailClientLogic() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];

        Test.startTest();
        String result = HandleVendorAbscondController.sendEmail(
            tpl.Id, 
            new List<String>{'client@test.com'}, 
            opp.Id, 
            'Client', 
            null
        );
        Test.stopTest();

        Assert.areEqual('SUCCESS', result, 'Client email send should return SUCCESS');
    }

    // -------------------------------------------------------------------
    // ✅ 3. Exception & Negative Tests
    // -------------------------------------------------------------------

    @isTest
    static void testSendEmailValidations() {
        Test.startTest();
        
        try {
            HandleVendorAbscondController.sendEmail(null, new List<String>{'a@a.com'}, null, 'Client', null);
            Assert.fail('Should throw exception for missing template');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Exception should be AuraHandledException');
        }

        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];
        try {
            HandleVendorAbscondController.sendEmail(tpl.Id, new List<String>(), null, 'Client', null);
            Assert.fail('Should throw exception for empty recipients');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Exception should be AuraHandledException');
        }

        try {
            HandleVendorAbscondController.sendEmail(tpl.Id, new List<String>{'', null}, null, 'Client', null);
            Assert.fail('Should throw exception for no valid emails found');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Exception should be AuraHandledException');
        }
        
        Test.stopTest();
    }

    @isTest
    static void testSendEmailCatchBlock() {
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];
        
        Test.startTest();
        try {
            HandleVendorAbscondController.sendEmail(
                tpl.Id, 
                new List<String>{'valid@email.com'}, 
                UserInfo.getUserId(), // Invalid WhatId for this template usage
                'Client', 
                null
            );
            Assert.fail('Should throw caught exception');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Exception should be AuraHandledException');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSendEmailSendFailure() {
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        List<String> badEmails = new List<String>{'invalidemail'}; 

        Test.startTest();
        try {
            HandleVendorAbscondController.sendEmail(tpl.Id, badEmails, opp.Id, 'Client', null);
        } catch (Exception e) {
            Boolean isHandled = e.getTypeName().contains('AuraHandledException') || 
                                e.getTypeName().contains('EmailException');
            Assert.isTrue(isHandled, 'Should catch send failure');
        }
        Test.stopTest();
    }
}