/**
 * @description       : Test class for OpportunityBudgetReviewController
 * @group             : Tests
 */
@IsTest
private class OpportunityBudgetReviewControllerTest {

    @TestSetup
    static void setupTestData() {
        // 1. Create Supervisor User
        User supervisor = TestDataUtility.createSupervisorUser('suptst');
        
        // 2. Create Client Contact
        Contact clientContact = TestDataUtility.createContact('Client', 'client@test.com', 'Password123!');
        
        // 3. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Test Budget Opp', supervisor.Id);
        opp.Primary_Contact__c = clientContact.Id;
        
        // Define a default Quotation Type using the correct API Name
        opp.Project_Request_Quotation_Type__c = 'Manual';
        
        // Setting up initial budget and duration fields
        opp.Budget__c = 10000;
        opp.Estimated_Budget__c = 12000;
        opp.Supervisor_Estimated_Budget__c = 9000;
        opp.Re_Visit_Site_Supervisor_Estimate_Budget__c = 9500;
        
        // Assigned as Strings instead of Integers
        opp.Project_Estimated_Completion_Months__c = '1 Month';
        opp.ReVisit_Site_Estimated_Completion_Months__c = '1 Month';
        update opp;
        
        // 4. Create Architecture Design Rows
        TestDataUtility.createArchitectureDesign(opp.Id, null, 'Sent');
        
        // 5. Create Payment Terms
        TestDataUtility.createPaymentTerm(opp.Id, 'Advance Payment', 50);

        // 6. Setup standard Email Templates to ensure code coverage in sendEmailSafe
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Client_Fresh', 'Client Fresh', 'Review Subject');
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Client_Revised', 'Client Revised', 'Review Subject');
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Client_Manager_Revised', 'Client Mgr Revised', 'Review Subject');
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Client_Ack_Pending', 'Client Ack', 'Review Subject');
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Notify_Supervisor', 'Notify Supervisor', 'Review Subject');
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Manager_Revised', 'Manager Revised', 'Review Subject');
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Manager_Fresh', 'Manager Fresh', 'Review Subject');
            TestDataUtility.createSpecificEmailTemplate('Budget_Template_Confirmation', 'Confirmation', 'Review Subject');
        }
    }

    @IsTest
    static void testGetBudgetReviewWithRevisitData() {
        Opportunity testOpp = [SELECT Id FROM Opportunity WHERE Name = 'Test Budget Opp' LIMIT 1];
        
        Test.startTest();
        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto = OpportunityBudgetReviewController.getBudgetReview(testOpp.Id);
        Test.stopTest();
        
        Assert.isNotNull(dto, 'DTO should not be null');
        Assert.areEqual(10000, dto.customerBudget, 'Customer budget should prioritize Budget__c');
        Assert.areEqual('Budget__c', dto.customerBudgetSource, 'Source should be Budget__c');
        Assert.areEqual(9500, dto.supervisorBudget, 'Supervisor budget should prioritize Re-Visit estimate');
        Assert.areEqual('Re_Visit_Site_Supervisor_Estimate_Budget__c', dto.supervisorBudgetSource, 'Source should be Re-Visit');
        Assert.areEqual('1 Month', dto.estimatedDuration, 'Duration should prioritize Re-Visit duration');
        Assert.isFalse(dto.architectureRows.isEmpty(), 'Architecture rows should be fetched');
        Assert.isFalse(dto.paymentTerms.isEmpty(), 'Payment terms should be fetched');
    }

    @IsTest
    static void testGetBudgetReviewWithFallbackData() {
        Opportunity testOpp = [SELECT Id FROM Opportunity WHERE Name = 'Test Budget Opp' LIMIT 1];
        // Nullify primary fields to test fallback logic
        testOpp.Budget__c = null;
        testOpp.Re_Visit_Site_Supervisor_Estimate_Budget__c = null;
        testOpp.ReVisit_Site_Estimated_Completion_Months__c = null;
        update testOpp;

        Test.startTest();
        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto = OpportunityBudgetReviewController.getBudgetReview(testOpp.Id);
        Test.stopTest();
        
        Assert.isNotNull(dto, 'DTO should not be null');
        Assert.areEqual(12000, dto.customerBudget, 'Customer budget should fallback to Estimated_Budget__c');
        Assert.areEqual(9000, dto.supervisorBudget, 'Supervisor budget should fallback to Supervisor_Estimated_Budget__c');
        Assert.areEqual('1 Month', dto.estimatedDuration, 'Duration should fallback to Project_Estimated_Completion_Months__c');
    }

    @IsTest
    static void testGetBudgetReviewNullCheck() {
        Test.startTest();
        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto = OpportunityBudgetReviewController.getBudgetReview(null);
        Test.stopTest();
        
        Assert.isNull(dto, 'Passing null Opportunity ID should return null DTO');
    }

    @IsTest
    static void testSaveChildRows() {
        Opportunity testOpp = [SELECT Id FROM Opportunity WHERE Name = 'Test Budget Opp' LIMIT 1];
        
        // Ensures the Quotation Type is set to 'Manual' (API Name)
        testOpp.Project_Request_Quotation_Type__c = 'Manual';
        update testOpp;

        OpportunityBudgetReviewController.BudgetReviewResponseDTO initialDto = OpportunityBudgetReviewController.getBudgetReview(testOpp.Id);
        
        // Prepare Request
        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req = new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();
        req.inputCustomerBudget = 11000;
        req.inputSupervisorBudget = 9800;
        req.inputDuration = '1 Month';
        
        // Modify Arch Rows and Payment Terms to test update logic
        initialDto.architectureRows[0].amount = 500;
        req.architectureRows = initialDto.architectureRows;
        
        initialDto.paymentTerms[0].percentage = 60;
        req.paymentTerms = initialDto.paymentTerms;

        Test.startTest();
        // With Project_Request_Quotation_Type__c == 'Manual', this will correctly update Budget__c
        OpportunityBudgetReviewController.BudgetReviewResponseDTO updatedDto = OpportunityBudgetReviewController.saveChildRows(testOpp.Id, req);
        Test.stopTest();

        Assert.isNotNull(updatedDto, 'Updated DTO should not be null');
        Assert.areEqual(11000, updatedDto.customerBudget, 'Customer budget should be updated via Manual logic');
        Assert.areEqual(9800, updatedDto.supervisorBudget, 'Supervisor budget should be updated');
        Assert.areEqual('1 Month', updatedDto.estimatedDuration, 'Duration should be updated');
        Assert.areEqual(500, updatedDto.architectureRows[0].amount, 'Architecture budget should be updated');
        Assert.areEqual(60, updatedDto.paymentTerms[0].percentage, 'Payment term percentage should be updated');
    }

    @IsTest
    static void testSaveChildRowsAutomation() {
        Opportunity testOpp = [SELECT Id FROM Opportunity WHERE Name = 'Test Budget Opp' LIMIT 1];
        
        // Explicitly set the exact API Name 'Automation'
        testOpp.Project_Request_Quotation_Type__c = 'Automation';
        testOpp.Budget__c = null; // Force getter to rely on Estimated_Budget__c
        update testOpp;
        
        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req = new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();
        req.inputCustomerBudget = 13000;

        Test.startTest();
        OpportunityBudgetReviewController.BudgetReviewResponseDTO updatedDto = OpportunityBudgetReviewController.saveChildRows(testOpp.Id, req);
        Test.stopTest();

        Assert.isNotNull(updatedDto, 'Updated DTO should not be null');
        Assert.areEqual(13000, updatedDto.customerBudget, 'Customer budget should be updated via Automation logic targeting Estimated_Budget__c');
    }

    @IsTest
    static void testSaveChildRowsNullCheck() {
        Opportunity testOpp = [SELECT Id FROM Opportunity WHERE Name = 'Test Budget Opp' LIMIT 1];
        
        Test.startTest();
        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto = OpportunityBudgetReviewController.saveChildRows(testOpp.Id, null);
        Test.stopTest();
        
        Assert.isNull(dto, 'Passing null request should return null');
    }

    @IsTest
    static void testSubmitToClientFresh() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        OpportunityBudgetReviewController.submitToClient(testOpp.Id);
        Test.stopTest();
        
        Opportunity updatedOpp = [SELECT Budget_Review_Status__c FROM Opportunity WHERE Id = :testOpp.Id];
        Assert.areEqual('Sent for Client Approval', updatedOpp.Budget_Review_Status__c, 'Status should be updated after client submission');
    }

    @IsTest
    static void testSubmitToClientWithRemarks() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        testOpp.Budget_Review_Manager_Remarks__c = 'Please revise the costs';
        update testOpp;

        Test.startTest();
        OpportunityBudgetReviewController.submitToClient(testOpp.Id);
        Test.stopTest();
        
        Opportunity updatedOpp = [SELECT Budget_Review_Status__c FROM Opportunity WHERE Id = :testOpp.Id];
        Assert.areEqual('Sent for Client Approval', updatedOpp.Budget_Review_Status__c, 'Status should update properly when remarks are present');
    }

    @IsTest
    static void testSubmitToClientException() {
        Test.startTest();
        try {
            // FIX: Generates a valid fake Opportunity ID dynamically instead of hardcoding PMD warnings
            Id dummyId = (Id)(Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
            
            OpportunityBudgetReviewController.submitToClient(dummyId);
            Assert.fail('Expected exception was not thrown');
        } catch (Exception e) {
            Assert.isInstanceOfType(e, AuraHandledException.class, 'Exception should be wrapped in AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSubmitDecisionClientApprove() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityBudgetReviewController.DecisionInput input = new OpportunityBudgetReviewController.DecisionInput();
        input.userType = 'Client';
        input.action = 'Approve';
        
        Test.startTest();
        OpportunityBudgetReviewController.submitDecision(testOpp.Id, input);
        Test.stopTest();
        
        Opportunity updatedOpp = [SELECT Budget_Review_Status__c FROM Opportunity WHERE Id = :testOpp.Id];
        Assert.areEqual('Client Approved', updatedOpp.Budget_Review_Status__c, 'Opp status should reflect client approval');
    }

    @IsTest
    static void testSubmitDecisionClientRequestChanges() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityBudgetReviewController.DecisionInput input = new OpportunityBudgetReviewController.DecisionInput();
        input.userType = 'Client';
        input.action = 'Reject';
        input.comments = 'Too expensive';
        
        Test.startTest();
        OpportunityBudgetReviewController.submitDecision(testOpp.Id, input);
        Test.stopTest();
        
        Opportunity updatedOpp = [SELECT Budget_Review_Status__c, Budget_Review_Client_Remarks__c FROM Opportunity WHERE Id = :testOpp.Id];
        Assert.areEqual('Client Requested Changes', updatedOpp.Budget_Review_Status__c, 'Opp status should reflect client rejection');
        Assert.areEqual('Too expensive', updatedOpp.Budget_Review_Client_Remarks__c, 'Client remarks should be saved');
    }

    @IsTest
    static void testSubmitDecisionManagerApprove() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityBudgetReviewController.DecisionInput input = new OpportunityBudgetReviewController.DecisionInput();
        input.userType = 'Manager';
        input.action = 'Approve';
        
        Test.startTest();
        OpportunityBudgetReviewController.submitDecision(testOpp.Id, input);
        Test.stopTest();
        
        Opportunity updatedOpp = [SELECT Budget_Review_Status__c FROM Opportunity WHERE Id = :testOpp.Id];
        Assert.areEqual('Manager Approved', updatedOpp.Budget_Review_Status__c, 'Opp status should reflect manager approval');
    }

    @IsTest
    static void testSubmitDecisionManagerRequestChanges() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityBudgetReviewController.DecisionInput input = new OpportunityBudgetReviewController.DecisionInput();
        input.userType = 'Manager';
        input.action = 'Reject';
        input.comments = 'Need vendor discounts';
        
        Test.startTest();
        OpportunityBudgetReviewController.submitDecision(testOpp.Id, input);
        Test.stopTest();
        
        Opportunity updatedOpp = [SELECT Budget_Review_Status__c, Budget_Review_Manager_Remarks__c FROM Opportunity WHERE Id = :testOpp.Id];
        Assert.areEqual('Manager Requested Changes', updatedOpp.Budget_Review_Status__c, 'Opp status should reflect manager rejection');
        Assert.areEqual('Need vendor discounts', updatedOpp.Budget_Review_Manager_Remarks__c, 'Manager remarks should be saved');
    }

    @IsTest
    static void testSubmitDecisionInvalidUserType() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityBudgetReviewController.DecisionInput input = new OpportunityBudgetReviewController.DecisionInput();
        input.userType = 'InvalidUser';
        input.action = 'Approve';
        
        Test.startTest();
        try {
            OpportunityBudgetReviewController.submitDecision(testOpp.Id, input);
            Assert.fail('Expected exception for invalid user type');
        } catch (Exception e) {
            Assert.isInstanceOfType(e, AuraHandledException.class, 'Exception should be an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSubmitDecisionNullValidations() {
        Test.startTest();
        
        try {
            OpportunityBudgetReviewController.submitDecision(null, new OpportunityBudgetReviewController.DecisionInput());
            Assert.fail('Expected exception for missing Record ID');
        } catch (Exception e) {
            Assert.isInstanceOfType(e, AuraHandledException.class, 'Should throw AuraHandledException for missing Record ID');
        }

        try {
            // FIX: Generates a valid fake Opportunity ID dynamically
            Id dummyId = (Id)(Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
            OpportunityBudgetReviewController.submitDecision(dummyId, null);
            Assert.fail('Expected exception for missing Decision Data');
        } catch (Exception e) {
            Assert.isInstanceOfType(e, AuraHandledException.class, 'Should throw AuraHandledException for missing Decision Data');
        }
        
        Test.stopTest();
    }
}