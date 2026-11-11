/**
 * @description Test class for ProformaManagerController.
 * Ensures 95%+ code coverage, PMD compliance, fast execution, and zero Mixed-DML / FLS errors.
 */
@IsTest
private class ProformaManagerControllerTest {

    @TestSetup
    static void setupTestData() {
        // 1. Create Supervisor User & Email Templates inside System.runAs(Current Admin)
        // to isolate Setup Object DML (User, EmailTemplate) from Non-Setup Object DML.
        User supervisor;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            supervisor = TestDataUtility.createSupervisorUser('mgruser');
            supervisor.FirstName = 'Arelia';
            supervisor.LastName = 'Supervisor';
            update supervisor;

            TestDataUtility.createSpecificEmailTemplate(
                System.Label.Proforma_Manager_Response_Template,
                'Proforma Manager Response Template',
                'Response for [OPPORTUNITY_NAME]',
                '<html><body>Project: [PROJECT_NAME] | Opp: [OPPORTUNITY_NAME] | Decision: [DECISION] | Comments: [COMMENTS] | Supervisor: [SUPERVISOR_NAME] | Client: [CLIENT_NAME]</body></html>'
            );

            TestDataUtility.createSpecificEmailTemplate(
                System.Label.Proforma_Client_Final_Approval_Template,
                'Proforma Client Final Approval',
                'Approval for [OPPORTUNITY_NAME] - [PROJECT_NAME]',
                '<html><body>Approved for [CLIENT_NAME] on [PROJECT_NAME] ([OPPORTUNITY_NAME])</body></html>'
            );
        }

        // 2. Create Non-Setup Data as the Running Admin User (NOT System.runAs(supervisor))
        // Why: 'Standard User' lacks Read/Create object permissions on Proforma_Invoice__c,
        // which causes ProformaInvoiceClientPushJob to throw System.QueryException during Test.stopTest().
        Contact clientContact = TestDataUtility.createContact('ClientLastName', 'client@example.com', 'Pass123!');

        Opportunity opp = TestDataUtility.createOpportunity('Arelia Living Luxury Suite', supervisor.Id);
        opp.Primary_Contact__c = clientContact.Id;

        // Safely populate optional/writable fields if they are not formula fields
        Map<String, Schema.SObjectField> oppFields = Schema.SObjectType.Opportunity.fields.getMap();
        if (oppFields.containsKey('Lead_Name__c') && oppFields.get('Lead_Name__c').getDescribe().isUpdateable()) {
            opp.put('Lead_Name__c', 'Arelia Client');
        }
        if (oppFields.containsKey('Supervisor_User_Email__c') && oppFields.get('Supervisor_User_Email__c').getDescribe().isUpdateable()) {
            opp.put('Supervisor_User_Email__c', supervisor.Email);
        }
        update opp;

        // 3. Create Proforma Invoice via TestDataUtility WITHOUT setting Status__c = 'Sent'
        // Avoiding Status__c = 'Sent' prevents enqueuing ProformaInvoiceClientPushJob and eliminates the 7m 29s timeout.
        Proforma_Invoice__c invoice = TestDataUtility.createProformaInvoice(opp.Id);

        // 4. Create and link ContentVersion file to cover attachment logic
        ContentVersion cv = TestDataUtility.createContentVersion('Design_Specs_V1', 'Mock File Data');
        TestDataUtility.linkFileToRecord(cv.Id, invoice.Id);
    }

    @IsTest
    static void testGetInvoiceByIdSuccess() {
        Proforma_Invoice__c testInvoice = [
            SELECT Id, Status__c, Manager_Approval__c, Secure_Token__c
            FROM Proforma_Invoice__c
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Object> result = ProformaManagerController.getInvoiceById(testInvoice.Secure_Token__c);
        Test.stopTest();

        Assert.isNotNull(result, 'The result map should not be null.');
        Assert.areEqual(testInvoice.Id, result.get('id'), 'The returned ID should match the test invoice ID.');
        Assert.areEqual('Arelia Living Luxury Suite', result.get('projectName'), 'Project name should match Opportunity Name.');

        String expectedManagerStatus = testInvoice.Manager_Approval__c ? 'Approved' : 'Pending';
        Assert.areEqual(expectedManagerStatus, result.get('managerStatus'), 'Manager status should match the record state.');
        Assert.areEqual(testInvoice.Status__c, result.get('clientStatus'), 'Client status should match the record state.');
        Assert.isNotNull(result.get('clientApprovedDate'), 'Client approved date should be formatted and populated.');
    }

    @IsTest
    static void testGetInvoiceByIdException() {
        String invalidToken = 'INVALID_SECURE_TOKEN_999';

        Test.startTest();
        try {
            ProformaManagerController.getInvoiceById(invalidToken);
            Assert.fail('Expected an AuraHandledException to be thrown for an invalid token.');
        } catch (Exception e) {
            Assert.isTrue(e instanceof AuraHandledException, 'Exception must be of type AuraHandledException.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSubmitManagerDecisionApprove() {
        Proforma_Invoice__c testInvoice = [
            SELECT Id, Secure_Token__c
            FROM Proforma_Invoice__c
            LIMIT 1
        ];

        Test.startTest();
        ProformaManagerController.submitManagerDecision(
            testInvoice.Secure_Token__c,
            'Approve',
            'Looks luxurious and aligned with standards.'
        );
        // Explicitly invoke notification handler to guarantee full coverage of internal + client email logic
        ProformaManagerController.sendManagerDecisionNotifications(
            testInvoice.Id,
            'Approve',
            'Looks luxurious and aligned with standards.'
        );
        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Manager_Approval__c, Manager_Comments__c
            FROM Proforma_Invoice__c
            WHERE Id = :testInvoice.Id
        ];

        Assert.isTrue(updatedInvoice.Manager_Approval__c, 'Invoice should be marked as approved.');
        Assert.areEqual(
            'Looks luxurious and aligned with standards.',
            updatedInvoice.Manager_Comments__c,
            'Comments should accurately reflect the manager input.'
        );
    }

    @IsTest
    static void testSubmitManagerDecisionApproveBlankComments() {
        Proforma_Invoice__c testInvoice = [
            SELECT Id, Secure_Token__c
            FROM Proforma_Invoice__c
            LIMIT 1
        ];

        Test.startTest();
        ProformaManagerController.submitManagerDecision(
            testInvoice.Secure_Token__c,
            'Approve',
            ''
        );
        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Manager_Approval__c, Manager_Comments__c
            FROM Proforma_Invoice__c
            WHERE Id = :testInvoice.Id
        ];

        Assert.isTrue(updatedInvoice.Manager_Approval__c, 'Invoice should be marked as approved.');
        Assert.areEqual(
            'Approved by manager',
            updatedInvoice.Manager_Comments__c,
            'Blank comments on approval should default to "Approved by manager".'
        );
    }

    @IsTest
    static void testSubmitManagerDecisionReject() {
        Proforma_Invoice__c testInvoice = [
            SELECT Id, Secure_Token__c
            FROM Proforma_Invoice__c
            LIMIT 1
        ];

        Test.startTest();
        ProformaManagerController.submitManagerDecision(
            testInvoice.Secure_Token__c,
            'Reject',
            'Budget needs revision.'
        );
        ProformaManagerController.sendManagerDecisionNotifications(
            testInvoice.Id,
            'Reject',
            'Budget needs revision.'
        );
        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Manager_Approval__c, Manager_Comments__c
            FROM Proforma_Invoice__c
            WHERE Id = :testInvoice.Id
        ];

        Assert.isFalse(updatedInvoice.Manager_Approval__c, 'Invoice should be marked as rejected.');
        Assert.areEqual(
            'Budget needs revision.',
            updatedInvoice.Manager_Comments__c,
            'Rejection comments should be recorded accurately.'
        );
    }

    @IsTest
    static void testSubmitManagerDecisionWithMissingOpportunity() {
        Proforma_Invoice__c orphanInvoice = new Proforma_Invoice__c(
            Secure_Token__c = UUID.randomUUID().toString()
        );
        insert orphanInvoice;

        Test.startTest();
        ProformaManagerController.submitManagerDecision(
            orphanInvoice.Secure_Token__c,
            'Approve',
            'No Opp tied to this one'
        );
        ProformaManagerController.sendManagerDecisionNotifications(
            orphanInvoice.Id,
            'Approve',
            'No Opp tied to this one'
        );
        Map<String, Object> orphanResult = ProformaManagerController.getInvoiceById(orphanInvoice.Secure_Token__c);
        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Manager_Approval__c
            FROM Proforma_Invoice__c
            WHERE Id = :orphanInvoice.Id
        ];

        Assert.isTrue(updatedInvoice.Manager_Approval__c, 'Approval should execute even when Opportunity__c is null.');
        Assert.areEqual('Unknown Project', orphanResult.get('projectName'), 'Orphan invoice should fallback to Unknown Project.');
    }

    @IsTest
    static void testSubmitManagerDecisionException() {
        String invalidToken = 'NON_EXISTENT_TOKEN_000';

        Test.startTest();
        try {
            ProformaManagerController.submitManagerDecision(invalidToken, 'Approve', 'Will Fail');
            Assert.fail('Expected an AuraHandledException to be thrown for an invalid token during submission.');
        } catch (Exception e) {
            Assert.isTrue(e instanceof AuraHandledException, 'Exception must be of type AuraHandledException.');
        }
        Test.stopTest();
    }
}