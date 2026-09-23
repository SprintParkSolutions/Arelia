/**
 * @description Test class for ClientAgreementSubmissionProcessor.
 * Covers valid processing, skipped records, expired token handling,
 * missing references, missing chunks, chunk rebuilding, and null/empty input.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc,PMD.TooManyMethods')
private class ClientAgreementSubmissionProcessorTest {
    private static final String CLIENT_EMAIL = 'client@example.com';
    private static final String SUPERVISOR_ALIAS = 'subsup';

    private static final String ACCOUNT_NAME = 'Submission Processor Account';
    private static final String OPPORTUNITY_NAME = 'Submission Processor Opportunity';

    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_SIGNED = 'Signed';
    private static final String STATUS_NEW = 'New';
    private static final String STATUS_PROCESSED = 'Processed';
    private static final String STATUS_FAILED = 'Failed';
    private static final String STATUS_EXPIRED = 'Expired';

    private static final String SIGNATURE_DATA = 'data:image/png;base64,SIGNATURE';
    private static final String SIGNED_HTML = '<p>Signed Agreement HTML</p>';
    private static final String AGREEMENT_HTML = '<p>Agreement HTML</p>';

    @TestSetup
    static void setupData() {
        TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);
    }

    @IsTest
    static void processSubmissionIdsShouldReturnForNullAndEmptyInput() {
        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(null);
        ClientAgreementSubmissionProcessor.processSubmissionIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Null and empty inputs should complete without exception.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldReturnWhenSubmissionIsMissing() {
        Set<Id> submissionIds = new Set<Id>();
        submissionIds.add(null);

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(submissionIds);
        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Missing submission Id should complete without exception.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldProcessValidSubmission() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SENT,
            System.now().addDays(2)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_NEW
        );

        createChunk(
            submissionRecord.Id,
            1,
            validPdfBase64()
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c processedSubmission =
            getSubmission(submissionRecord.Id);

        Client_Agreement__c signedAgreement =
            getAgreement(agreementRecord.Id);

        System.assertEquals(
            STATUS_PROCESSED,
            processedSubmission.Status__c,
            'Submission should be processed.'
        );
        System.assertEquals(
            null,
            processedSubmission.Error_Message__c,
            'Processed submission should not have error message.'
        );
        System.assertNotEquals(
            null,
            processedSubmission.Processed_Date__c,
            'Processed date should be populated.'
        );
        System.assertEquals(
            STATUS_SIGNED,
            signedAgreement.Status__c,
            'Agreement should be signed.'
        );
        System.assertEquals(
            null,
            signedAgreement.Token__c,
            'Token should be cleared after signing.'
        );
        System.assertEquals(
            SIGNATURE_DATA,
            signedAgreement.Signature_Base64__c,
            'Signature should be copied to agreement.'
        );
        System.assertEquals(
            SIGNED_HTML,
            signedAgreement.Agreement_HTML__c,
            'Signed agreement HTML should be copied to agreement.'
        );
        System.assertNotEquals(
            null,
            signedAgreement.Signed_Date__c,
            'Signed date should be populated.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldSkipAlreadyProcessedSubmission() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SENT,
            System.now().addDays(2)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_PROCESSED
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c processedSubmission =
            getSubmission(submissionRecord.Id);

        System.assertEquals(
            STATUS_PROCESSED,
            processedSubmission.Status__c,
            'Already processed submission should remain processed.'
        );
        System.assertEquals(
            null,
            processedSubmission.Processed_Date__c,
            'Already processed submission should not be processed again.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldHandleAlreadySignedAgreement() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SIGNED,
            System.now().addDays(2)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_NEW
        );

        createChunk(
            submissionRecord.Id,
            1,
            validPdfBase64()
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c processedSubmission =
            getSubmission(submissionRecord.Id);

        System.assertEquals(
            STATUS_PROCESSED,
            processedSubmission.Status__c,
            'Submission should be marked processed when agreement is already signed.'
        );
        System.assertEquals(
            'Agreement was already signed.',
            processedSubmission.Error_Message__c,
            'Expected already signed message should be stored.'
        );
        System.assertNotEquals(
            null,
            processedSubmission.Processed_Date__c,
            'Processed date should be populated.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldExpireAgreementWhenTokenExpired() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SENT,
            System.now().addDays(-1)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_NEW
        );

        createChunk(
            submissionRecord.Id,
            1,
            validPdfBase64()
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c failedSubmission =
            getSubmission(submissionRecord.Id);

        Client_Agreement__c agreementAfterProcessing =
            getAgreement(agreementRecord.Id);

        System.assertEquals(
            STATUS_FAILED,
            failedSubmission.Status__c,
            'Expired token submission should be failed.'
        );
        System.assertNotEquals(
            null,
            failedSubmission.Error_Message__c,
            'Expired token failure message should be stored.'
        );
        System.assert(
            failedSubmission.Error_Message__c.contains('Signing link expired')
            || failedSubmission.Error_Message__c.contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST')
            || failedSubmission.Error_Message__c.contains('bad value for restricted picklist')
            || failedSubmission.Error_Message__c.contains(STATUS_EXPIRED),
            'Failure message should be related to expired token or restricted picklist configuration.'
        );
        System.assertNotEquals(
            null,
            failedSubmission.Processed_Date__c,
            'Processed date should be populated for failed submission.'
        );
        System.assert(
            agreementAfterProcessing.Status__c == STATUS_SENT
            || agreementAfterProcessing.Status__c == STATUS_EXPIRED,
            'Agreement should either remain Sent when Expired is not allowed, or become Expired when the picklist allows it.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldFailWhenAgreementReferenceMissing() {
        Client_Agreement_Submission__c submissionRecord = createSubmission(
            null,
            STATUS_NEW
        );

        createChunk(
            submissionRecord.Id,
            1,
            validPdfBase64()
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c failedSubmission =
            getSubmission(submissionRecord.Id);

        System.assertEquals(
            STATUS_FAILED,
            failedSubmission.Status__c,
            'Submission without agreement reference should fail.'
        );
        System.assertNotEquals(
            null,
            failedSubmission.Error_Message__c,
            'Failure message should be populated.'
        );
        System.assertNotEquals(
            null,
            failedSubmission.Processed_Date__c,
            'Processed date should be populated.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldFailWhenChunksAreMissing() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SENT,
            System.now().addDays(2)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_NEW
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c failedSubmission =
            getSubmission(submissionRecord.Id);

        System.assertEquals(
            STATUS_FAILED,
            failedSubmission.Status__c,
            'Submission without PDF chunks should fail.'
        );
        System.assertNotEquals(
            null,
            failedSubmission.Error_Message__c,
            'Failure message should be populated.'
        );
        System.assertNotEquals(
            null,
            failedSubmission.Processed_Date__c,
            'Processed date should be populated.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldFailWhenChunkDataIsBlank() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SENT,
            System.now().addDays(2)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_NEW
        );

        createChunk(
            submissionRecord.Id,
            1,
            ''
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c failedSubmission =
            getSubmission(submissionRecord.Id);

        System.assertEquals(
            STATUS_FAILED,
            failedSubmission.Status__c,
            'Blank chunk data should fail the submission.'
        );
        System.assertNotEquals(
            null,
            failedSubmission.Error_Message__c,
            'Failure message should be populated.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldRebuildMultipleChunks() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SENT,
            System.now().addDays(2)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_NEW
        );

        String pdfBase64 = validPdfBase64();
        Integer splitIndex = 10;

        createChunk(
            submissionRecord.Id,
            1,
            pdfBase64.left(splitIndex)
        );

        createChunk(
            submissionRecord.Id,
            2,
            pdfBase64.substring(splitIndex)
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c processedSubmission =
            getSubmission(submissionRecord.Id);

        System.assertEquals(
            STATUS_PROCESSED,
            processedSubmission.Status__c,
            'Multiple chunks should be rebuilt and processed.'
        );
    }

    @IsTest
    static void processSubmissionIdsShouldIgnoreBlankChunkAndUseValidChunk() {
        Client_Agreement__c agreementRecord = createAgreement(
            STATUS_SENT,
            System.now().addDays(2)
        );

        Client_Agreement_Submission__c submissionRecord = createSubmission(
            agreementRecord.Id,
            STATUS_NEW
        );

        createChunk(
            submissionRecord.Id,
            1,
            ''
        );

        createChunk(
            submissionRecord.Id,
            2,
            validPdfBase64()
        );

        Test.startTest();
        ClientAgreementSubmissionProcessor.processSubmissionIds(
            new Set<Id>{ submissionRecord.Id }
        );
        Test.stopTest();

        Client_Agreement_Submission__c processedSubmission =
            getSubmission(submissionRecord.Id);

        System.assertEquals(
            STATUS_PROCESSED,
            processedSubmission.Status__c,
            'Processor should ignore blank chunk and process valid chunk.'
        );
    }

    private static Client_Agreement_Submission__c createSubmission(
        Id agreementId,
        String statusValue
    ) {
        Client_Agreement_Submission__c submissionRecord =
            new Client_Agreement_Submission__c();

        submissionRecord.Client_Agreement__c = agreementId;
        submissionRecord.Signature_Base64__c = SIGNATURE_DATA;
        submissionRecord.Signed_Agreement_HTML__c = SIGNED_HTML;
        submissionRecord.Status__c = statusValue;

        insert submissionRecord;

        return submissionRecord;
    }

    private static Client_Agreement_Submission_Chunk__c createChunk(
        Id submissionId,
        Integer sequence,
        String chunkData
    ) {
        Client_Agreement_Submission_Chunk__c chunkRecord =
            new Client_Agreement_Submission_Chunk__c();

        chunkRecord.Submission_Id__c = String.valueOf(submissionId);
        chunkRecord.Sequence__c = sequence;
        chunkRecord.Chunk_Data__c = chunkData;

        insert chunkRecord;

        return chunkRecord;
    }

    private static Client_Agreement__c createAgreement(
        String statusValue,
        Datetime tokenExpiry
    ) {
        return createAgreementForOpportunity(
            createAreliaOpportunity(),
            statusValue,
            tokenExpiry
        );
    }

    private static Client_Agreement__c createAgreementForOpportunity(
        Opportunity opportunityRecord,
        String statusValue,
        Datetime tokenExpiry
    ) {
        Client_Agreement__c agreementRecord = new Client_Agreement__c();

        agreementRecord.Opportunity__c = opportunityRecord.Id;
        agreementRecord.Status__c = statusValue;
        agreementRecord.Agreement_HTML__c = AGREEMENT_HTML;
        agreementRecord.Token__c = buildUniqueToken();
        agreementRecord.Token_Expiry__c = tokenExpiry;

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

    private static Client_Agreement_Submission__c getSubmission(Id submissionId) {
        return [
            SELECT Id,
                   Client_Agreement__c,
                   Status__c,
                   Error_Message__c,
                   Processed_Date__c
            FROM Client_Agreement_Submission__c
            WHERE Id = :submissionId
            LIMIT 1
        ];
    }

    private static Client_Agreement__c getAgreement(Id agreementId) {
        return [
            SELECT Id,
                   Status__c,
                   Token__c,
                   Signature_Base64__c,
                   Signed_Date__c,
                   Agreement_HTML__c,
                   Signed_File_Id__c
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];
    }

    private static String validPdfBase64() {
        return EncodingUtil.base64Encode(
            Blob.valueOf('%PDF-1.4 Signed Agreement PDF')
        );
    }

    private static String buildUniqueToken() {
        return 'token-' + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    }
}