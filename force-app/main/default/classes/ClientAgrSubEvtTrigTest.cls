/**
 * @description Test class for ClientAgreementSubmissionEventTrigger.
 * Covers blank, null, invalid, and valid platform event submission ids.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc')
private class ClientAgrSubEvtTrigTest {
    private static final String SUPERVISOR_ALIAS = 'evttrg';
    private static final String CLIENT_EMAIL = 'client@example.com';

    private static final String ACCOUNT_NAME = 'Submission Event Account';
    private static final String OPPORTUNITY_NAME = 'Submission Event Opportunity';

    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_PROCESSED = 'Processed';

    private static final String SIGNATURE_DATA = 'data:image/png;base64,SIGNATURE';
    private static final String SIGNED_HTML = '<p>Signed Agreement HTML</p>';
    private static final String AGREEMENT_HTML = '<p>Agreement HTML</p>';

    @TestSetup
    static void setupData() {
        TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);
    }

    @IsTest
    static void triggerShouldIgnoreBlankNullAndInvalidSubmissionIds() {
        List<Client_Agreement_Submission_Event__e> eventRecords =
            new List<Client_Agreement_Submission_Event__e>{
                createEvent(null),
                createEvent(''),
                createEvent('12345')
            };

        Test.startTest();
        List<Database.SaveResult> results = EventBus.publish(eventRecords);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(
            3,
            results.size(),
            'Three platform event results should be returned.'
        );

        assertPublishResults(results);
    }

    @IsTest
    static void triggerShouldProcessValidSubmissionId() {
        Client_Agreement_Submission__c submissionRecord =
            createProcessedSubmission();

        List<Client_Agreement_Submission_Event__e> eventRecords =
            new List<Client_Agreement_Submission_Event__e>{
                createEvent(String.valueOf(submissionRecord.Id))
            };

        Test.startTest();
        List<Database.SaveResult> results = EventBus.publish(eventRecords);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(
            1,
            results.size(),
            'One platform event result should be returned.'
        );

        assertPublishResults(results);

        Client_Agreement_Submission__c updatedSubmission = [
            SELECT Id,
                   Status__c,
                   Client_Agreement__c
            FROM Client_Agreement_Submission__c
            WHERE Id = :submissionRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_PROCESSED,
            updatedSubmission.Status__c,
            'Processed submission should remain unchanged.'
        );

        System.assertNotEquals(
            null,
            updatedSubmission.Client_Agreement__c,
            'Submission should have a valid agreement reference.'
        );
    }

    private static Client_Agreement_Submission_Event__e createEvent(
        String submissionIdValue
    ) {
        Client_Agreement_Submission_Event__e eventRecord =
            new Client_Agreement_Submission_Event__e();

        eventRecord.Submission_Id__c = submissionIdValue;

        return eventRecord;
    }

    private static Client_Agreement_Submission__c createProcessedSubmission() {
        Client_Agreement__c agreementRecord = createAgreement();

        Client_Agreement_Submission__c submissionRecord =
            new Client_Agreement_Submission__c();

        submissionRecord.Client_Agreement__c = agreementRecord.Id;
        submissionRecord.Signature_Base64__c = SIGNATURE_DATA;
        submissionRecord.Signed_Agreement_HTML__c = SIGNED_HTML;
        submissionRecord.Status__c = STATUS_PROCESSED;

        insert submissionRecord;

        return submissionRecord;
    }

    private static Client_Agreement__c createAgreement() {
        Opportunity opportunityRecord = createAreliaOpportunity();

        Client_Agreement__c agreementRecord = new Client_Agreement__c();

        agreementRecord.Opportunity__c = opportunityRecord.Id;
        agreementRecord.Status__c = STATUS_SENT;
        agreementRecord.Agreement_HTML__c = AGREEMENT_HTML;
        agreementRecord.Token__c = buildUniqueToken();
        agreementRecord.Token_Expiry__c = System.now().addDays(2);

        insert agreementRecord;

        return agreementRecord;
    }

    private static Opportunity createAreliaOpportunity() {
        Account accountRecord = TestDataUtility.createAccount(ACCOUNT_NAME);

        User supervisorUser = [
            SELECT Id
            FROM User
            WHERE Alias = :SUPERVISOR_ALIAS
            LIMIT 1
        ];

        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            OPPORTUNITY_NAME,
            supervisorUser.Id
        );

        opportunityRecord.AccountId = accountRecord.Id;
        opportunityRecord.Email__c = CLIENT_EMAIL;

        update opportunityRecord;

        System.assertEquals(
            AreliaUtility.getAreliaOpportunityRecordTypeId(),
            opportunityRecord.RecordTypeId,
            'Opportunity should keep Arelia Record Type from TestDataUtility.'
        );

        return opportunityRecord;
    }

    private static void assertPublishResults(List<Database.SaveResult> results) {
        for (Database.SaveResult result : results) {
            System.assertEquals(
                true,
                result.isSuccess(),
                getPublishError(result)
            );
        }
    }

    private static String getPublishError(Database.SaveResult result) {
        if (result == null || result.isSuccess() || result.getErrors().isEmpty()) {
            return 'Platform event publish should succeed.';
        }

        return result.getErrors()[0].getMessage();
    }

    private static String buildUniqueToken() {
        return 'token-' + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    }
}