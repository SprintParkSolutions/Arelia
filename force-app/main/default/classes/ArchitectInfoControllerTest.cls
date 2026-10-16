/**
 * @description       : Test class for ArchitectInfoController, including the OpportunityAfterUpdate
 *                       trigger path that sends the architect email regardless of update source.
 * @group             : Tests
 **/
@IsTest
private class ArchitectInfoControllerTest {

    private static final String TEMPLATE_DEV_NAME = 'Architect_Opportunity_Mail';

    @TestSetup
    static void setup() {
        User supervisor = TestDataUtility.createSupervisorUser('ArchSup');
        TestDataUtility.createOpportunity('Architect Test Opportunity', supervisor.Id);

        // EmailTemplate is a "setup" object - its DML cannot be mixed with non-setup
        // object DML (like the Opportunity above) in the same transaction, or Salesforce
        // throws MIXED_DML_OPERATION. System.runAs() opens a fresh mixed-DML scope.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                TEMPLATE_DEV_NAME,
                'Architect Opportunity Mail',
                'Architect Details Updated'
            );
        }
    }

    @IsTest
    static void testUpdateAndSendEmailUpdatesFieldsAndSendsEmailViaTrigger() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        ArchitectInfoController.updateAndSendEmail(opp.Id, 'Jane Architect', 'architect@test.com', '9998887777');
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Opportunity updated = [
            SELECT Architect_Name__c, Architect_Email__c, Architect_Contact__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        Assert.areEqual('Jane Architect', updated.Architect_Name__c, 'Architect name should be saved.');
        Assert.areEqual('architect@test.com', updated.Architect_Email__c, 'Architect email should be saved.');
        Assert.areEqual('9998887777', updated.Architect_Contact__c, 'Architect phone should be saved.');
        Assert.areEqual(
            initialEmails + 1,
            finalEmails,
            'Saving all three architect fields should trigger exactly one email via OpportunityAfterUpdate.'
        );
    }

    @IsTest
    static void testUpdateAndSendEmailMissingParametersThrows() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        try {
            ArchitectInfoController.updateAndSendEmail(null, 'Jane Architect', 'architect@test.com', '9998887777');
            Assert.fail('Null recordId should throw an exception.');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('required'), 'Should surface the missing parameters message.');
        }

        try {
            ArchitectInfoController.updateAndSendEmail(opp.Id, 'Jane Architect', '', '9998887777');
            Assert.fail('Blank architect email should throw an exception.');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('required'), 'Should surface the missing parameters message.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateAndSendEmailUnsupportedRecordTypeThrows() {
        Account nonOpportunity = TestDataUtility.createAccount('Not An Opportunity');

        Test.startTest();
        try {
            ArchitectInfoController.updateAndSendEmail(
                nonOpportunity.Id,
                'Jane Architect',
                'architect@test.com',
                '9998887777'
            );
            Assert.fail('Non-Opportunity record should be rejected.');
        } catch (AuraHandledException ex) {
            Assert.isTrue(
                ex.getMessage().contains('Arelia opportunities'),
                'Should surface the unsupported record type message.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateAndSendEmailDoesNotBlockSaveWhenTemplateMissing() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        ArchitectInfoController.templateDeveloperName = 'Nonexistent_Architect_Template';

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        ArchitectInfoController.updateAndSendEmail(opp.Id, 'Jane Architect', 'architect@test.com', '9998887777');
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Opportunity updated = [SELECT Architect_Email__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual(
            'architect@test.com',
            updated.Architect_Email__c,
            'Field save should succeed even when the email template is missing.'
        );
        Assert.areEqual(initialEmails, finalEmails, 'No email should be sent when the template cannot be found.');
    }

    @IsTest
    static void testSendArchitectEmailsSkipsWhenFieldsPartiallyPopulated() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Architect_Name__c = 'Jane Architect';
        opp.Architect_Email__c = 'architect@test.com';
        // Architect_Contact__c intentionally left blank so the record does not fully qualify.

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        update opp;
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(
            initialEmails,
            finalEmails,
            'No email should be sent while any of the three architect fields is blank.'
        );
    }

    @IsTest
    static void testSendArchitectEmailsSkipsWhenFieldsUnchanged() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Architect_Name__c = 'Jane Architect';
        opp.Architect_Email__c = 'architect@test.com';
        opp.Architect_Contact__c = '9998887777';
        update opp;

        opp.Name = 'Renamed Opportunity';

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        update opp;
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(
            initialEmails,
            finalEmails,
            'Unrelated field updates should not resend the architect email.'
        );
    }

}