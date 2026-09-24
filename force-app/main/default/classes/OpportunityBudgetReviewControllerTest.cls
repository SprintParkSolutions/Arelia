/**
 * @description Verifies budget retrieval, budget persistence, child-row updates,
 * approval decisions, validation behavior and estimated budget description
 * persistence for OpportunityBudgetReviewController.
 * @group Tests
 */
@IsTest
private class OpportunityBudgetReviewControllerTest {

    /**
     * @description Creates shared test data using TestDataUtility.
     */
    @TestSetup
    static void setupTestData() {
        User supervisor =
            TestDataUtility.createSupervisorUser('suptst');

        Contact clientContact =
            TestDataUtility.createContact(
                'Client',
                'client@test.com',
                'Password123!'
            );

        Opportunity opp =
            TestDataUtility.createOpportunity(
                'Test Budget Opp',
                supervisor.Id
            );

        opp.Primary_Contact__c = clientContact.Id;
        opp.Project_Request_Quotation_Type__c = 'Manual';
        opp.Estimated_Budget_Description__c = 'Initial estimate';
        opp.Budget__c = 10000;
        opp.Estimated_Budget__c = 12000;
        opp.Supervisor_Estimated_Budget__c = 9000;
        opp.Re_Visit_Site_Supervisor_Estimate_Budget__c = 9500;
        opp.Project_Estimated_Completion_Months__c = '1 Month';
        opp.ReVisit_Site_Estimated_Completion_Months__c = '1 Month';

        update opp;

        TestDataUtility.createArchitectureDesign(
            opp.Id,
            null,
            'Sent'
        );

        TestDataUtility.createPaymentTerm(
            opp.Id,
            'Advance Payment',
            50
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Client_Fresh',
                'Client Fresh',
                'Review Subject'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Client_Revised',
                'Client Revised',
                'Review Subject'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Client_Manager_Revised',
                'Client Manager Revised',
                'Review Subject'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Client_Ack_Pending',
                'Client Acknowledgement',
                'Review Subject'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Notify_Supervisor',
                'Notify Supervisor',
                'Review Subject'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Manager_Revised',
                'Manager Revised',
                'Review Subject'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Manager_Fresh',
                'Manager Fresh',
                'Review Subject'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Budget_Template_Confirmation',
                'Confirmation',
                'Review Subject'
            );
        }
    }

    /**
     * @description Verifies retrieval of revisit values and description.
     */
    @IsTest
    static void testGetBudgetReviewWithRevisitData() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto =
            OpportunityBudgetReviewController.getBudgetReview(
                testOpp.Id
            );

        Test.stopTest();

        Assert.isNotNull(dto, 'DTO should not be null');

        Assert.areEqual(
            'Initial estimate',
            dto.estimatedBudgetDescription,
            'Description should load from Opportunity'
        );

        Assert.areEqual(
            10000,
            dto.customerBudget,
            'Customer budget should prioritize Budget__c'
        );

        Assert.areEqual(
            'Budget__c',
            dto.customerBudgetSource,
            'Customer budget source should be Budget__c'
        );

        Assert.areEqual(
            9500,
            dto.supervisorBudget,
            'Supervisor budget should prioritize revisit budget'
        );

        Assert.areEqual(
            'Re_Visit_Site_Supervisor_Estimate_Budget__c',
            dto.supervisorBudgetSource,
            'Supervisor source should be revisit budget'
        );

        Assert.areEqual(
            '1 Month',
            dto.estimatedDuration,
            'Duration should prioritize revisit duration'
        );

        Assert.isFalse(
            dto.architectureRows.isEmpty(),
            'Architecture rows should be returned'
        );

        Assert.isFalse(
            dto.paymentTerms.isEmpty(),
            'Payment terms should be returned'
        );
    }

    /**
     * @description Verifies fallback budget and duration values.
     */
    @IsTest
    static void testGetBudgetReviewWithFallbackData() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        testOpp.Budget__c = null;
        testOpp.Re_Visit_Site_Supervisor_Estimate_Budget__c = null;
        testOpp.ReVisit_Site_Estimated_Completion_Months__c = null;

        update testOpp;

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto =
            OpportunityBudgetReviewController.getBudgetReview(
                testOpp.Id
            );

        Test.stopTest();

        Assert.isNotNull(dto, 'DTO should not be null');

        Assert.areEqual(
            12000,
            dto.customerBudget,
            'Customer budget should fallback to Estimated_Budget__c'
        );

        Assert.areEqual(
            9000,
            dto.supervisorBudget,
            'Supervisor budget should fallback to Supervisor_Estimated_Budget__c'
        );

        Assert.areEqual(
            '1 Month',
            dto.estimatedDuration,
            'Duration should fallback to project duration'
        );
    }

    /**
     * @description Verifies null budget and duration values.
     */
    @IsTest
    static void testGetBudgetReviewWithNoBudgetData() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        testOpp.Budget__c = null;
        testOpp.Estimated_Budget__c = null;
        testOpp.Supervisor_Estimated_Budget__c = null;
        testOpp.Re_Visit_Site_Supervisor_Estimate_Budget__c = null;
        testOpp.Project_Estimated_Completion_Months__c = null;
        testOpp.ReVisit_Site_Estimated_Completion_Months__c = null;

        update testOpp;

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto =
            OpportunityBudgetReviewController.getBudgetReview(
                testOpp.Id
            );

        Test.stopTest();

        Assert.isNull(
            dto.customerBudget,
            'Customer budget should be null'
        );

        Assert.isNull(
            dto.supervisorBudget,
            'Supervisor budget should be null'
        );

        Assert.isNull(
            dto.estimatedDuration,
            'Duration should be null'
        );
    }

    /**
     * @description Verifies null Opportunity ID handling.
     */
    @IsTest
    static void testGetBudgetReviewNullCheck() {
        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto =
            OpportunityBudgetReviewController.getBudgetReview(null);

        Test.stopTest();

        Assert.isNull(
            dto,
            'Null Opportunity ID should return null'
        );
    }

    /**
     * @description Verifies manual budget, supervisor budget, duration,
     * architecture budget and payment term updates.
     */
    @IsTest
    static void testSaveChildRows() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        testOpp.Project_Request_Quotation_Type__c = 'Manual';
        update testOpp;

        OpportunityBudgetReviewController.BudgetReviewResponseDTO initialDto =
            OpportunityBudgetReviewController.getBudgetReview(
                testOpp.Id
            );

        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req =
            new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();

        req.inputCustomerBudget = 11000;
        req.inputSupervisorBudget = 9800;
        req.inputDuration = '1 Month';

        initialDto.architectureRows[0].amount = 500;
        req.architectureRows = initialDto.architectureRows;

        initialDto.paymentTerms[0].percentage = 60;
        req.paymentTerms = initialDto.paymentTerms;

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO updatedDto =
            OpportunityBudgetReviewController.saveChildRows(
                testOpp.Id,
                req
            );

        Test.stopTest();

        Assert.isNotNull(
            updatedDto,
            'Updated DTO should not be null'
        );

        Assert.areEqual(
            11000,
            updatedDto.customerBudget,
            'Manual customer budget should be updated'
        );

        Assert.areEqual(
            9800,
            updatedDto.supervisorBudget,
            'Supervisor budget should be updated'
        );

        Assert.areEqual(
            '1 Month',
            updatedDto.estimatedDuration,
            'Duration should be updated'
        );

        Assert.areEqual(
            500,
            updatedDto.architectureRows[0].amount,
            'Architecture budget should be updated'
        );

        Assert.areEqual(
            60,
            updatedDto.paymentTerms[0].percentage,
            'Payment percentage should be updated'
        );
    }

    /**
     * @description Verifies automation quotation updates Estimated_Budget__c.
     */
    @IsTest
    static void testSaveChildRowsAutomation() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        testOpp.Project_Request_Quotation_Type__c = 'Automation';
        testOpp.Budget__c = null;

        update testOpp;

        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req =
            new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();

        req.inputCustomerBudget = 13000;

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO updatedDto =
            OpportunityBudgetReviewController.saveChildRows(
                testOpp.Id,
                req
            );

        Test.stopTest();

        Assert.isNotNull(
            updatedDto,
            'Updated DTO should not be null'
        );

        Assert.areEqual(
            13000,
            updatedDto.customerBudget,
            'Automation budget should update Estimated_Budget__c'
        );
    }

    /**
     * @description Verifies null save request handling.
     */
    @IsTest
    static void testSaveChildRowsNullCheck() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto =
            OpportunityBudgetReviewController.saveChildRows(
                testOpp.Id,
                null
            );

        Test.stopTest();

        Assert.isNull(
            dto,
            'Null request should return null'
        );
    }

    /**
     * @description Verifies fresh submission status.
     */
    @IsTest
    static void testSubmitToClientFresh() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        Test.startTest();

        OpportunityBudgetReviewController.submitToClient(
            testOpp.Id
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :testOpp.Id
        ];

        Assert.areEqual(
            'Sent for Client Approval',
            updatedOpp.Budget_Review_Status__c,
            'Budget status should be updated'
        );
    }

    /**
     * @description Verifies submission when manager remarks exist.
     */
    @IsTest
    static void testSubmitToClientWithRemarks() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        testOpp.Budget_Review_Manager_Remarks__c =
            'Please revise the costs';

        update testOpp;

        Test.startTest();

        OpportunityBudgetReviewController.submitToClient(
            testOpp.Id
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :testOpp.Id
        ];

        Assert.areEqual(
            'Sent for Client Approval',
            updatedOpp.Budget_Review_Status__c,
            'Status should update with manager remarks'
        );
    }

    /**
     * @description Verifies submission when client remarks exist.
     */
    @IsTest
    static void testSubmitToClientWithClientRemarks() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        testOpp.Budget_Review_Client_Remarks__c =
            'Client requested a previous revision';

        update testOpp;

        Test.startTest();

        OpportunityBudgetReviewController.submitToClient(
            testOpp.Id
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :testOpp.Id
        ];

        Assert.areEqual(
            'Sent for Client Approval',
            updatedOpp.Budget_Review_Status__c,
            'Status should update with client remarks'
        );
    }

    /**
     * @description Verifies unsupported parent record validation.
     */
    @IsTest
    static void testUnsupportedOpportunityValidation() {
        Account accountRecord =
            TestDataUtility.createAccount(
                'Unsupported Budget Account'
            );

        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req =
            new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();

        req.inputCustomerBudget = 100;

        Test.startTest();

        try {
            OpportunityBudgetReviewController.saveChildRows(
                accountRecord.Id,
                req
            );

            Assert.fail(
                'Unsupported parent should throw an exception'
            );
        } catch (Exception e) {
            Assert.isInstanceOfType(
                e,
                AuraHandledException.class,
                'Exception should be AuraHandledException'
            );
        }

        Test.stopTest();
    }

    /**
     * @description Verifies invalid Opportunity ID handling.
     */
    @IsTest
    static void testSubmitToClientException() {
        Test.startTest();

        try {
            Id dummyId = (Id)(
                Opportunity.SObjectType.getDescribe().getKeyPrefix() +
                '000000000000'
            );

            OpportunityBudgetReviewController.submitToClient(
                dummyId
            );

            Assert.fail(
                'Expected AuraHandledException was not thrown'
            );
        } catch (Exception e) {
            Assert.isInstanceOfType(
                e,
                AuraHandledException.class,
                'Exception should be AuraHandledException'
            );
        }

        Test.stopTest();
    }

    /**
     * @description Verifies client approval.
     */
    @IsTest
    static void testSubmitDecisionClientApprove() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityBudgetReviewController.DecisionInput input =
            new OpportunityBudgetReviewController.DecisionInput();

        input.userType = 'Client';
        input.action = 'Approve';

        Test.startTest();

        OpportunityBudgetReviewController.submitDecision(
            testOpp.Id,
            input
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :testOpp.Id
        ];

        Assert.areEqual(
            'Client Approved',
            updatedOpp.Budget_Review_Status__c,
            'Client approval status should be saved'
        );
    }

    /**
     * @description Verifies client change requests and remarks.
     */
    @IsTest
    static void testSubmitDecisionClientRequestChanges() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityBudgetReviewController.DecisionInput input =
            new OpportunityBudgetReviewController.DecisionInput();

        input.userType = 'Client';
        input.action = 'Reject';
        input.comments = 'Too expensive';

        Test.startTest();

        OpportunityBudgetReviewController.submitDecision(
            testOpp.Id,
            input
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT
                Budget_Review_Status__c,
                Budget_Review_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :testOpp.Id
        ];

        Assert.areEqual(
            'Client Requested Changes',
            updatedOpp.Budget_Review_Status__c,
            'Client change status should be saved'
        );

        Assert.areEqual(
            'Too expensive',
            updatedOpp.Budget_Review_Client_Remarks__c,
            'Client remarks should be saved'
        );
    }

    /**
     * @description Verifies manager approval.
     */
    @IsTest
    static void testSubmitDecisionManagerApprove() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityBudgetReviewController.DecisionInput input =
            new OpportunityBudgetReviewController.DecisionInput();

        input.userType = 'Manager';
        input.action = 'Approve';

        Test.startTest();

        OpportunityBudgetReviewController.submitDecision(
            testOpp.Id,
            input
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :testOpp.Id
        ];

        Assert.areEqual(
            'Manager Approved',
            updatedOpp.Budget_Review_Status__c,
            'Manager approval status should be saved'
        );
    }

    /**
     * @description Verifies manager change requests and remarks.
     */
    @IsTest
    static void testSubmitDecisionManagerRequestChanges() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityBudgetReviewController.DecisionInput input =
            new OpportunityBudgetReviewController.DecisionInput();

        input.userType = 'Manager';
        input.action = 'Reject';
        input.comments = 'Need vendor discounts';

        Test.startTest();

        OpportunityBudgetReviewController.submitDecision(
            testOpp.Id,
            input
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT
                Budget_Review_Status__c,
                Budget_Review_Manager_Remarks__c
            FROM Opportunity
            WHERE Id = :testOpp.Id
        ];

        Assert.areEqual(
            'Manager Requested Changes',
            updatedOpp.Budget_Review_Status__c,
            'Manager change status should be saved'
        );

        Assert.areEqual(
            'Need vendor discounts',
            updatedOpp.Budget_Review_Manager_Remarks__c,
            'Manager remarks should be saved'
        );
    }

    /**
     * @description Verifies invalid decision-maker validation.
     */
    @IsTest
    static void testSubmitDecisionInvalidUserType() {
        Opportunity testOpp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityBudgetReviewController.DecisionInput input =
            new OpportunityBudgetReviewController.DecisionInput();

        input.userType = 'InvalidUser';
        input.action = 'Approve';

        Test.startTest();

        try {
            OpportunityBudgetReviewController.submitDecision(
                testOpp.Id,
                input
            );

            Assert.fail(
                'Invalid user type should throw an exception'
            );
        } catch (Exception e) {
            Assert.isInstanceOfType(
                e,
                AuraHandledException.class,
                'Exception should be AuraHandledException'
            );
        }

        Test.stopTest();
    }

    /**
     * @description Verifies null decision validation.
     */
    @IsTest
    static void testSubmitDecisionNullValidations() {
        Test.startTest();

        try {
            OpportunityBudgetReviewController.submitDecision(
                null,
                new OpportunityBudgetReviewController.DecisionInput()
            );

            Assert.fail(
                'Missing record ID should throw an exception'
            );
        } catch (Exception e) {
            Assert.isInstanceOfType(
                e,
                AuraHandledException.class,
                'Exception should be AuraHandledException'
            );
        }

        try {
            Id dummyId = (Id)(
                Opportunity.SObjectType.getDescribe().getKeyPrefix() +
                '000000000000'
            );

            OpportunityBudgetReviewController.submitDecision(
                dummyId,
                null
            );

            Assert.fail(
                'Missing decision data should throw an exception'
            );
        } catch (Exception e) {
            Assert.isInstanceOfType(
                e,
                AuraHandledException.class,
                'Exception should be AuraHandledException'
            );
        }

        Test.stopTest();
    }

    /**
     * @description Verifies multiline estimated budget description persistence.
     */
    @IsTest
    static void testSaveEstimatedBudgetDescription() {
        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req =
            new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();

        req.updateEstimatedBudgetDescription = true;
        req.inputEstimatedBudgetDescription =
            'Premium materials.\nIncludes installation.';

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto =
            OpportunityBudgetReviewController.saveChildRows(
                opp.Id,
                req
            );

        Test.stopTest();

        Opportunity saved = [
            SELECT Estimated_Budget_Description__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Assert.areEqual(
            req.inputEstimatedBudgetDescription,
            saved.Estimated_Budget_Description__c,
            'Description should persist'
        );

        Assert.areEqual(
            req.inputEstimatedBudgetDescription,
            dto.estimatedBudgetDescription,
            'Response should contain the saved description'
        );
    }

    /**
     * @description Verifies the estimated budget description can be cleared.
     */
    @IsTest
    static void testClearEstimatedBudgetDescription() {
        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req =
            new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();

        req.updateEstimatedBudgetDescription = true;
        req.inputEstimatedBudgetDescription = null;

        Test.startTest();

        OpportunityBudgetReviewController.BudgetReviewResponseDTO dto =
            OpportunityBudgetReviewController.saveChildRows(
                opp.Id,
                req
            );

        Test.stopTest();

        Opportunity saved = [
            SELECT Estimated_Budget_Description__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Assert.isNull(
            saved.Estimated_Budget_Description__c,
            'Description should be cleared'
        );

        Assert.isNull(
            dto.estimatedBudgetDescription,
            'Response should contain a cleared description'
        );
    }

    /**
     * @description Verifies callers that omit description updates preserve the
     * existing Opportunity description.
     */
    @IsTest
    static void testPreserveDescriptionWhenOmitted() {
        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Budget Opp'
            LIMIT 1
        ];

        OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO req =
            new OpportunityBudgetReviewController.BudgetReviewSaveRequestDTO();

        req.inputSupervisorBudget = 9700;

        Test.startTest();

        OpportunityBudgetReviewController.saveChildRows(
            opp.Id,
            req
        );

        Test.stopTest();

        Opportunity saved = [
            SELECT Estimated_Budget_Description__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Assert.areEqual(
            'Initial estimate',
            saved.Estimated_Budget_Description__c,
            'Description should remain unchanged'
        );
    }
}