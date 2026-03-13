/**
 * @description Test class for ProformaManagerController.
 * Ensures maximum coverage, PMD compliance, and strict assertion enforcement.
 */
@IsTest
private class ProformaManagerControllerTest {

    @TestSetup
    static void setupTestData() {
        // 1. Create User
        User supervisor = TestDataUtility.createSupervisorUser('mgruser');

        // 2. Insert Templates (requires System.runAs(Admin) to avoid Mixed DML)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                System.Label.Proforma_Manager_Response_Template,
                'Proforma Manager Response Template',
                'Response for [OPPORTUNITY_NAME]',
                '<html><body>Decision: [DECISION] <br/> Comments: [COMMENTS] <br/> Supervisor: [SUPERVISOR_NAME]</body></html>'
            );
            
            TestDataUtility.createSpecificEmailTemplate(
                System.Label.Proforma_Client_Final_Approval_Template,
                'Proforma Client Final Approval',
                'Approval for [OPPORTUNITY_NAME]',
                '<html><body>Approved for [CLIENT_NAME] on [PROJECT_NAME]</body></html>'
            );
        }

        // 3. Create Contact, Opportunity & Invoice Data AS THE SUPERVISOR
        // This prevents the cross-reference entity sharing error.
        System.runAs(supervisor) {
            // Moved inside the runAs block!
            Contact clientContact = TestDataUtility.createContact('ClientLastName', 'client@example.com', 'Pass123!');

            Opportunity opp = TestDataUtility.createOpportunity('Arelia Living Luxury Suite', supervisor.Id);
            opp.Primary_Contact__c = clientContact.Id;
            
            // Gracefully attempt to populate fields used by the controller, if they are writable
            try { opp.put('Lead_Name__c', 'Arelia Client'); } catch (Exception e) { /* Ignored if formula */ }
            try { opp.put('Supervisor_User_Email__c', supervisor.Email); } catch (Exception e) { /* Ignored if formula */ }
            update opp;

            Proforma_Invoice__c invoice = TestDataUtility.createProformaInvoice(opp.Id);
            invoice.Status__c = 'Sent';
            update invoice;

            // 4. Create and link a file to cover attachment logic
            ContentVersion cv = TestDataUtility.createContentVersion('Design_Specs_V1', 'Mock File Data');
            TestDataUtility.linkFileToRecord(cv.Id, invoice.Id);
        }
    }

    @IsTest
    static void testGetInvoiceByIdSuccess() {
        // Query the necessary fields to compare against the dynamic org defaults
        Proforma_Invoice__c testInvoice = [SELECT Id, Status__c, Manager_Approval__c FROM Proforma_Invoice__c LIMIT 1];

        Test.startTest();
        Map<String, Object> result = ProformaManagerController.getInvoiceById(testInvoice.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'The result map should not be null.');
        Assert.areEqual(testInvoice.Id, result.get('id'), 'The returned ID should match the test invoice ID.');
        
        // Dynamically assert the manager status based on the actual record's boolean value
        String expectedManagerStatus = testInvoice.Manager_Approval__c ? 'Approved' : 'Pending';
        Assert.areEqual(expectedManagerStatus, result.get('managerStatus'), 'Manager status should match the record state.');
        
        // Check client status safely against the record
        Assert.areEqual(testInvoice.Status__c, result.get('clientStatus'), 'Client status should match the record state.');
    }
    
    @IsTest
    static void testGetInvoiceByIdException() {
        Id fakeId = 'a00000000000000AAA'; // Fake 18-character ID to force a QueryException

        Test.startTest();
        try {
            ProformaManagerController.getInvoiceById(fakeId);
            Assert.fail('Expected an AuraHandledException to be thrown for an invalid ID.');
        } catch (Exception e) {
            Assert.isTrue(e instanceof AuraHandledException, 'Exception must be of type AuraHandledException.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSubmitManagerDecisionApprove() {
        Proforma_Invoice__c testInvoice = [SELECT Id FROM Proforma_Invoice__c LIMIT 1];

        Test.startTest();
        ProformaManagerController.submitManagerDecision(testInvoice.Id, 'Approve', 'Looks luxurious and aligned with standards.');
        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Manager_Approval__c, Manager_Comments__c 
            FROM Proforma_Invoice__c 
            WHERE Id = :testInvoice.Id
        ];
        
        Assert.isTrue(updatedInvoice.Manager_Approval__c, 'Invoice should be marked as approved.');
        Assert.areEqual('Looks luxurious and aligned with standards.', updatedInvoice.Manager_Comments__c, 'Comments should accurately reflect the manager input.');
    }

    @IsTest
    static void testSubmitManagerDecisionReject() {
        Proforma_Invoice__c testInvoice = [SELECT Id FROM Proforma_Invoice__c LIMIT 1];

        Test.startTest();
        ProformaManagerController.submitManagerDecision(testInvoice.Id, 'Reject', 'Budget needs revision.');
        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Manager_Approval__c, Manager_Comments__c 
            FROM Proforma_Invoice__c 
            WHERE Id = :testInvoice.Id
        ];
        
        Assert.isFalse(updatedInvoice.Manager_Approval__c, 'Invoice should be marked as rejected.');
        Assert.areEqual('Budget needs revision.', updatedInvoice.Manager_Comments__c, 'Rejection comments should be recorded accurately.');
    }

    @IsTest
    static void testSubmitManagerDecisionWithMissingOpportunity() {
        // This test specifically covers the early return block inside the notification logic 
        // to ensure it fails safely and coverage hits those specific conditional branches.
        Proforma_Invoice__c orphanInvoice = new Proforma_Invoice__c();
        insert orphanInvoice;

        Test.startTest();
        ProformaManagerController.submitManagerDecision(orphanInvoice.Id, 'Approve', 'No Opp tied to this one');
        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Manager_Approval__c 
            FROM Proforma_Invoice__c 
            WHERE Id = :orphanInvoice.Id
        ];
        
        Assert.isTrue(updatedInvoice.Manager_Approval__c, 'Approval should still execute locally even if notification dependencies are missing.');
    }

        @IsTest
    static void testSubmitManagerDecisionException() {
        Id fakeId = 'a00000000000000AAA';

        Test.startTest();
        try {
            ProformaManagerController.submitManagerDecision(fakeId, 'Approve', 'Will Fail');
            Assert.fail('Expected an AuraHandledException to be thrown for an invalid ID during submission.');
        } catch (Exception e) {
            // AuraHandledException messages are masked as "Script-thrown exception" in test context.
            // Asserting the instance type is the reliable way to pass this check.
            Assert.isTrue(e instanceof AuraHandledException, 'Exception must be of type AuraHandledException.');
        }
        Test.stopTest();
    }
}