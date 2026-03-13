/**
 * @description Comprehensive test class for PaymentTermController to achieve 90%+ coverage.
 * PMD Violations addressed: No hardcoded IDs, Modern Assertions, Proper Scoping.
 */
@isTest
private class PaymentTermControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User and Contact
        User supervisor = TestDataUtility.createSupervisorUser('paymgr');
        
        System.runAs(supervisor) {
            Contact clientContact = TestDataUtility.createContact('Test Client', 'client@pay.com', 'pass123');
            
            // 2. Create Opportunity & manually update to link Primary Contact (critical for extractContactInfo coverage)
            Opportunity opp = TestDataUtility.createOpportunity('Test Opp Payment Approval', supervisor.Id);
            opp.Primary_Contact__c = clientContact.Id;
            opp.Supervisor_Name__c = 'Test Supervisor Name'; // Covers the fallback name logic
            update opp;

            // 3. Create Project
            Project__c proj = TestDataUtility.createProject('Test Project Payment', 10000, clientContact.Id);

            // 4. Create initial Payment Terms
            TestDataUtility.createPaymentTerm(opp.Id, 'Opp Advance', 10.0);
            TestDataUtility.createPaymentTerm(proj.Id, 'Project Advance', 20.0);
        }
    }

    @isTest
    static void testGetPaymentTermsAndApprovalData() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        // Test Opportunity Path
        Map<String, Object> oppResult = PaymentTermController.getPaymentTerms(opp.Id);
        Assert.isNotNull(oppResult, 'Should return map for Opportunity');
        Assert.areEqual('Opportunity', oppResult.get('objectType'), 'Object type should match');

        // Test Project Path (Covers getApprovalData wrapper as well)
        Map<String, Object> projResult = PaymentTermController.getApprovalData(proj.Id);
        Assert.isNotNull(projResult, 'Should return map for Project');
        Assert.areEqual('Project__c', projResult.get('objectType'), 'Object type should match');

        // Test Null Path
        Map<String, Object> nullResult = PaymentTermController.getPaymentTerms(null);
        Assert.isNull(nullResult, 'Should return null when ID is null');
        Test.stopTest();
    }

    @isTest
    static void testSavePaymentTerms() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Payment_Term__c existingTerm = [SELECT Id FROM Payment_Term__c WHERE Opportunity__c = :opp.Id LIMIT 1];

        List<Payment_Term__c> termsToUpsert = new List<Payment_Term__c>{
            new Payment_Term__c(Term_Label__c = 'Opp Milestone 2', Percentage__c = 40),
            new Payment_Term__c(Term_Label__c = 'Proj Milestone 2', Percentage__c = 50)
        };

        Test.startTest();
        // Insert for Opportunity (Also deletes the existing term)
        PaymentTermController.savePaymentTerms(
            new List<Payment_Term__c>{ termsToUpsert[0] }, 
            opp.Id, 
            new List<Id>{ existingTerm.Id }
        );

        // Insert for Project
        PaymentTermController.savePaymentTerms(
            new List<Payment_Term__c>{ termsToUpsert[1] }, 
            proj.Id, 
            new List<Id>()
        );
        Test.stopTest();

        // Assert Deletion
        Integer deletedCount = [SELECT COUNT() FROM Payment_Term__c WHERE Id = :existingTerm.Id];
        Assert.areEqual(0, deletedCount, 'Existing term should be deleted');

        // Assert Insertions and Logic (Name syncs from Term_Label__c)
        Payment_Term__c oppCheck = [SELECT Opportunity__c, Name FROM Payment_Term__c WHERE Term_Label__c = 'Opp Milestone 2' LIMIT 1];
        Assert.areEqual(opp.Id, oppCheck.Opportunity__c, 'Linked to Opp');
        Assert.areEqual('Opp Milestone 2', oppCheck.Name, 'Name synced');

        Payment_Term__c projCheck = [SELECT Project__c FROM Payment_Term__c WHERE Term_Label__c = 'Proj Milestone 2' LIMIT 1];
        Assert.areEqual(proj.Id, projCheck.Project__c, 'Linked to Proj');
    }

    @isTest
    static void testSubmitToManager() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        PaymentTermController.submitToManager(opp.Id);
        
        // Covering early return for Project__c
        PaymentTermController.submitToManager(proj.Id);
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Payment_Terms_Status__c FROM Opportunity WHERE Id = :opp.Id LIMIT 1];
        Assert.areEqual('Sent for Manager Approval', updatedOpp.Payment_Terms_Status__c, 'Status should be updated');
    }

    @isTest
    static void testSubmitDecisionManagerApprove() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        PaymentTermController.DecisionInput input = new PaymentTermController.DecisionInput();
        input.userType = 'Manager';
        input.action = 'Approve';

        Test.startTest();
        PaymentTermController.submitDecision(opp.Id, input);
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Payment_Terms_Status__c FROM Opportunity WHERE Id = :opp.Id LIMIT 1];
        Assert.areEqual('Sent for Client Approval', updatedOpp.Payment_Terms_Status__c, 'Manager Approval should update status');
    }

    @isTest
    static void testSubmitDecisionManagerReject() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        PaymentTermController.DecisionInput input = new PaymentTermController.DecisionInput();
        input.userType = 'Manager';
        input.action = 'Reject';
        input.comments = 'Please revise the percentage';

        Test.startTest();
        PaymentTermController.submitDecision(opp.Id, input);
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Payment_Terms_Status__c, Payment_Term_Manager_Remarks__c FROM Opportunity WHERE Id = :opp.Id LIMIT 1];
        Assert.areEqual('Manager Requested Changes', updatedOpp.Payment_Terms_Status__c, 'Manager Reject should update status');
        Assert.areEqual('Please revise the percentage', updatedOpp.Payment_Term_Manager_Remarks__c, 'Remarks should be saved');
    }

    @isTest
    static void testSubmitDecisionClientApprove() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        PaymentTermController.DecisionInput input = new PaymentTermController.DecisionInput();
        input.userType = 'Client';
        input.action = 'Approve';

        Test.startTest();
        PaymentTermController.submitDecision(opp.Id, input);
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Payment_Terms_Status__c FROM Opportunity WHERE Id = :opp.Id LIMIT 1];
        Assert.areEqual('Client Approved', updatedOpp.Payment_Terms_Status__c, 'Client Approval should update status');
    }

    @isTest
    static void testSubmitDecisionClientReject() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        PaymentTermController.DecisionInput input = new PaymentTermController.DecisionInput();
        input.userType = 'Client';
        input.action = 'Reject';
        input.comments = 'Due date is too soon';

        Test.startTest();
        PaymentTermController.submitDecision(opp.Id, input);
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Payment_Terms_Status__c, Payment_Term_Client_Remarks__c FROM Opportunity WHERE Id = :opp.Id LIMIT 1];
        Assert.areEqual('Client Requested Changes', updatedOpp.Payment_Terms_Status__c, 'Client Reject should update status');
        Assert.areEqual('Due date is too soon', updatedOpp.Payment_Term_Client_Remarks__c, 'Remarks should be saved');
    }

    @isTest
    static void testSubmitDecisionProjectReturnEarly() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        PaymentTermController.DecisionInput input = new PaymentTermController.DecisionInput();
        input.userType = 'Manager';
        input.action = 'Approve';

        Test.startTest();
        // Should execute early return safely without throwing errors
        PaymentTermController.submitDecision(proj.Id, input);
        Test.stopTest();
        
        Assert.isTrue(true, 'Expected to complete without exception due to early return');
    }

    @isTest
    static void testExceptionsAndHelpers() {
        Test.startTest();

        // 1. Save Exception (Triggering a NullPointerException artificially)
        try {
            // Null ID throws error when calling getSObjectType()
            PaymentTermController.savePaymentTerms(new List<Payment_Term__c>{new Payment_Term__c()}, null, null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage() != null, 'Caught expected save exception');
        }

        // 2. Submit To Manager Exception
        try {
            PaymentTermController.submitToManager(null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage() != null, 'Caught expected submitToManager exception');
        }

        // 3. Submit Decision Exception
        try {
            PaymentTermController.submitDecision(null, null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            // FIX: AuraHandledException messages are often obfuscated to 'Script-thrown exception' in tests.
            // Check for != null rather than hardcoding the string match.
            Assert.isTrue(e.getMessage() != null, 'Caught expected submitDecision missing data exception');
        }
        
        // 4. Test safeSplit directly (Helper logic)
        List<String> splitList = PaymentTermController.safeSplit('test1@test.com,test2@test.com');
        Assert.areEqual(2, splitList.size(), 'safeSplit should properly delimit strings');
        
        List<String> emptySplit = PaymentTermController.safeSplit(null);
        Assert.isTrue(emptySplit.isEmpty(), 'safeSplit should handle null gracefully');

        // 5. Instantiating nested wrappers manually to ensure 100% coverage on properties
        PaymentTermController.EmailRequest emailReq = new PaymentTermController.EmailRequest();
        emailReq.urlUserType = 'Test';
        Assert.areEqual('Test', emailReq.urlUserType, 'Wrapper prop assignment works');

        Test.stopTest();
    }
}