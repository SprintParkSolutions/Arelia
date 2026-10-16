/**
 * @description Test class for ClientAgreementPublicController.
 * Covers public agreement loading by token and Id, signed/expired link states,
 * signature submission, PDF chunk creation, validation failures,
 * and Agreement Preview supporting-image filtering.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc,PMD.TooManyMethods')
private class ClientAgreementPublicControllerTest {

    private static final String CLIENT_EMAIL = 'client@example.com';
    private static final String SUPERVISOR_ALIAS = 'pubsup';
    private static final String ACCOUNT_NAME = 'Public Agreement Account';
    private static final String OPPORTUNITY_NAME = 'Public Agreement Opportunity';
    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_SIGNED = 'Signed';
    private static final String AGREEMENT_HTML = '<p>Agreement Body</p>';
    private static final String SIGNED_HTML = '<p>Signed HTML</p>';
    private static final String SIGNATURE_DATA = 'data:image/png;base64,SIGNATURE';

    private class SubmitParams {
        Id agreementId;
        String signatureBase64;
        String signedAgreementHtml;
        String signedPdfBase64;
    }


    /*
     * ============================================================
     * TEST SETUP
     *
     * IMPORTANT:
     * Existing TestDataUtility usage is intentionally preserved.
     * ============================================================
     */
    @TestSetup
    static void setupData() {

        TestDataUtility.createSupervisorUser(
            SUPERVISOR_ALIAS
        );
    }


    /*
     * ============================================================
     * EXISTING SUCCESS TEST - TOKEN
     * ============================================================
     */
    @IsTest
    static void getAgreementByTokenShouldReturnSuccess() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'token-success', System.now().addDays(2));

        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse response = ClientAgreementPublicController.getAgreementByToken('token-success');
        Test.stopTest();

        System.assertEquals(true, response.valid, 'Valid token should return valid response.');
        System.assertEquals('Success', response.message, 'Valid token should return success message.');
        System.assertEquals(agreementRecord.Id, response.agreementId, 'Response agreement Id should match created agreement.');
        System.assertEquals(AGREEMENT_HTML, response.agreementHtml, 'Agreement HTML should be returned.');
        System.assertEquals(CLIENT_EMAIL, response.clientEmail, 'Client email should be returned.');
        System.assertNotEquals(null, response.supervisorEmail, 'Supervisor email should be returned.');
        System.assertEquals(STATUS_SENT, response.status, 'Agreement status should be returned.');
        System.assertNotEquals(null, response.supportingFiles, 'Supporting files list should not be null.');

        /*
         * No supporting image is referenced in the default
         * AGREEMENT_HTML, so the new filtering logic should
         * return an empty list.
         */
        System.assertEquals(0, response.supportingFiles.size(), 'Default agreement HTML should not return unreferenced supporting images.');
    }


    /*
     * ============================================================
     * EXISTING SUCCESS TEST - ID
     * ============================================================
     */
    @IsTest
    static void getAgreementByIdShouldReturnSuccess() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'id-success', System.now().addDays(2));

        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse response = ClientAgreementPublicController.getAgreementById(agreementRecord.Id);
        Test.stopTest();

        System.assertEquals(true, response.valid, 'Valid agreement Id should return valid response.');
        System.assertEquals('Success', response.message, 'Valid agreement Id should return success message.');
        System.assertEquals(agreementRecord.Id, response.agreementId, 'Agreement Id should match.');
        System.assertEquals(AGREEMENT_HTML, response.agreementHtml, 'Agreement HTML should be returned.');
        System.assertNotEquals(null, response.supportingFiles, 'Supporting files list should not be null.');
        System.assertEquals(0, response.supportingFiles.size(), 'Unreferenced Opportunity images should not automatically appear in Agreement Preview.');
    }


    /*
     * ============================================================
     * NEW TEST:
     *
     * Token-based Agreement Preview should return only an image
     * genuinely referenced in Agreement_HTML__c.
     *
     * Another image may remain stored on Opportunity but must
     * not appear in the Agreement Preview.
     * ============================================================
     */
    @IsTest
    static void getAgreementByTokenShouldReturnOnlyReferencedSupportingImage() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'token-image-filter', System.now().addDays(2));

        /*
         * Image that should remain part of Agreement Preview.
         */
        ContentVersion referencedImage =
            createContentVersion(
                'Referenced Preview Image',
                'referenced-preview.png',
                Blob.valueOf(
                    'Referenced Preview Image Content'
                ),
                agreementRecord.Opportunity__c
            );

        /*
         * Simulates an image removed from the
         * Supporting Images / PDFs component.
         *
         * The Salesforce File remains linked to Opportunity,
         * but its Id is not present in Agreement_HTML__c.
         */
        ContentVersion removedImage =
            createContentVersion(
                'Removed Supporting Image',
                'removed-supporting.jpg',
                Blob.valueOf(
                    'Removed Supporting Image Content'
                ),
                agreementRecord.Opportunity__c
            );

        String referencedDocumentId = String.valueOf(referencedImage.ContentDocumentId);

        /*
         * Only the referenced image is part of Agreement_HTML__c.
         */
        agreementRecord.Agreement_HTML__c =
            '<p>Agreement Body</p>' +
            '<img src="/sfc/servlet.shepherd/document/download/' +
            referencedDocumentId +
            '" />';

        update agreementRecord;
        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse response = ClientAgreementPublicController.getAgreementByToken('token-image-filter');
        Test.stopTest();

        System.assertEquals(true, response.valid, 'Agreement should remain valid.');
        System.assertEquals('Success', response.message);
        System.assertNotEquals(null, response.supportingFiles, 'Supporting files should not be null.');
        System.assertEquals(1, response.supportingFiles.size(), 'Only the image referenced in Agreement HTML should appear in Agreement Preview.');
        System.assertEquals('Referenced Preview Image.png', response.supportingFiles[0].fileName, 'Referenced image should be returned.');
        System.assertEquals(referencedDocumentId, response.supportingFiles[0].contentDocumentId, 'Returned image should match referenced ContentDocumentId.');
        System.assertEquals(false, containsSupportingFile(response.supportingFiles, 'Removed Supporting Image.jpg'), 'Removed/unreferenced supporting image must not appear in Agreement Preview.');

        /*
         * Critical requirement:
         *
         * Verify the removed image was NOT deleted from Salesforce
         * and is still linked to the Opportunity.
         */
        List<ContentDocumentLink> removedImageLinks = [SELECT Id, ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId = :agreementRecord.Opportunity__c AND ContentDocumentId = :removedImage.ContentDocumentId];
        System.assertEquals(1, removedImageLinks.size(), 'Removed supporting image must remain linked to the Opportunity.');
    }


    /*
     * ============================================================
     * NEW TEST:
     *
     * Verify identical filtering when Agreement Preview is loaded
     * using Agreement Id instead of token.
     * ============================================================
     */
    @IsTest
    static void getAgreementByIdShouldReturnOnlyReferencedSupportingImage() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'id-image-filter', System.now().addDays(2));

        ContentVersion referencedImage =
            createContentVersion(
                'Id Referenced Image',
                'id-referenced.png',
                Blob.valueOf(
                    'Id Referenced Image Content'
                ),
                agreementRecord.Opportunity__c
            );

        ContentVersion unreferencedImage =
            createContentVersion(
                'Id Removed Image',
                'id-removed.jpg',
                Blob.valueOf(
                    'Id Removed Image Content'
                ),
                agreementRecord.Opportunity__c
            );

        String referencedVersionId = String.valueOf(referencedImage.Id);

        /*
         * ClientAgreementAttachmentService supports both
         * ContentDocumentId and ContentVersionId references.
         *
         * Use ContentVersionId here to also verify that path
         * through ClientAgreementPublicController.
         */
        agreementRecord.Agreement_HTML__c =
            '<p>Agreement Body</p>' +
            '<img src="/sfc/servlet.shepherd/version/download/' +
            referencedVersionId +
            '" />';

        update agreementRecord;
        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse response = ClientAgreementPublicController.getAgreementById(agreementRecord.Id);
        Test.stopTest();

        System.assertEquals(true, response.valid, 'Agreement should be valid when loaded by Id.');
        System.assertEquals('Success', response.message);
        System.assertNotEquals(null, response.supportingFiles, 'Supporting files should not be null.');
        System.assertEquals(1, response.supportingFiles.size(), 'Only referenced image should be returned by Id-based Agreement Preview.');
        System.assertEquals('Id Referenced Image.png', response.supportingFiles[0].fileName);
        System.assertEquals(referencedVersionId, response.supportingFiles[0].contentVersionId, 'Image referenced by ContentVersionId should be returned.');
        System.assertEquals(false, containsSupportingFile(response.supportingFiles, 'Id Removed Image.jpg'), 'Unreferenced/removed image must not appear in Id-based Agreement Preview.');

        /*
         * Confirm excluded file remains in Salesforce.
         */
        List<ContentDocumentLink> remainingLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :agreementRecord.Opportunity__c AND ContentDocumentId = :unreferencedImage.ContentDocumentId];
        System.assertEquals(1, remainingLinks.size(), 'Excluded supporting image must remain linked to Opportunity.');
    }


    /*
     * ============================================================
     * NEW TEST:
     *
     * Opportunity may contain one or multiple supporting images,
     * but if Agreement_HTML__c does not reference them they must
     * not appear in the public Agreement Preview.
     * ============================================================
     */
    @IsTest
    static void getAgreementShouldExcludeAllUnreferencedSupportingImages() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'all-images-removed-token', System.now().addDays(2));

        ContentVersion firstImage =
            createContentVersion(
                'First Removed Image',
                'first-removed.png',
                Blob.valueOf(
                    'First Removed Image'
                ),
                agreementRecord.Opportunity__c
            );

        ContentVersion secondImage =
            createContentVersion(
                'Second Removed Image',
                'second-removed.jpg',
                Blob.valueOf(
                    'Second Removed Image'
                ),
                agreementRecord.Opportunity__c
            );

        /*
         * Neither Salesforce File Id is referenced.
         */
        agreementRecord.Agreement_HTML__c = '<p>Agreement Body without supporting images.</p>';
        update agreementRecord;

        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse tokenResponse = ClientAgreementPublicController.getAgreementByToken('all-images-removed-token');
        ClientAgreementDTO.PublicAgreementResponse idResponse = ClientAgreementPublicController.getAgreementById(agreementRecord.Id);
        Test.stopTest();

        System.assertEquals(true, tokenResponse.valid);
        System.assertEquals(0, tokenResponse.supportingFiles.size(), 'Removed/unreferenced images must not appear when loading by token.');
        System.assertEquals(true, idResponse.valid);
        System.assertEquals(0, idResponse.supportingFiles.size(), 'Removed/unreferenced images must not appear when loading by Id.');

        /*
         * Verify both files still physically exist on Opportunity.
         */
        Set<Id> removedDocumentIds = new Set<Id>{firstImage.ContentDocumentId, secondImage.ContentDocumentId};
        List<ContentDocumentLink> remainingLinks = [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :agreementRecord.Opportunity__c AND ContentDocumentId IN :removedDocumentIds];
        System.assertEquals(2, remainingLinks.size(), 'Removing files from Client Agreement selection must not delete or unlink Opportunity Files.');
    }


    /*
     * ============================================================
     * EXISTING VALIDATION TESTS
     * ============================================================
     */
    @IsTest
    static void getAgreementByTokenShouldHandleBlankToken() {

        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse blankResponse = ClientAgreementPublicController.getAgreementByToken('');
        Test.stopTest();
        System.assertEquals(false, blankResponse.valid, 'Blank token should return invalid response.');
        System.assertEquals('Invalid signing link.', blankResponse.message, 'Blank token should return invalid signing link message.');
    }


    @IsTest
    static void getAgreementByTokenShouldHandleInvalidToken() {

        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse invalidResponse = ClientAgreementPublicController.getAgreementByToken('invalid-token-no-record');
        Test.stopTest();
        System.assertEquals(false, invalidResponse.valid, 'Invalid token should return invalid response.');
        System.assertEquals('Invalid or expired signing link.', invalidResponse.message, 'Invalid token should return invalid or expired message.');
    }


    @IsTest
    static void getAgreementByIdShouldHandleNullId() {

        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse response = ClientAgreementPublicController.getAgreementById(null);
        Test.stopTest();
        System.assertEquals(false, response.valid, 'Null agreement Id should return invalid response.');
        System.assertEquals('Invalid signing link.', response.message, 'Null agreement Id should return invalid signing link message.');
    }


    @IsTest
    static void getAgreementByIdShouldHandleDeletedAgreement() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'deleted-id-token', System.now().addDays(2));

        Id deletedAgreementId = agreementRecord.Id;
        delete agreementRecord;
        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse response = ClientAgreementPublicController.getAgreementById(deletedAgreementId);

        Test.stopTest();
        System.assertEquals(false, response.valid, 'Deleted agreement Id should return invalid response.');
        System.assertEquals('Invalid or expired signing link.', response.message, 'Deleted agreement should return invalid or expired message.');
    }


    @IsTest
    static void getAgreementShouldReturnAlreadySignedMessage() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED, 'signed-token', System.now().addDays(2));

        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse tokenResponse = ClientAgreementPublicController.getAgreementByToken('signed-token');
        ClientAgreementDTO.PublicAgreementResponse idResponse = ClientAgreementPublicController.getAgreementById(agreementRecord.Id);
        Test.stopTest();

        System.assertEquals(false, tokenResponse.valid, 'Signed agreement should not be valid by token.');
        System.assertEquals('This agreement has already been signed.', tokenResponse.message, 'Signed token should return already signed message.');
        System.assertEquals(false, idResponse.valid, 'Signed agreement should not be valid by Id.');
        System.assertEquals('This agreement has already been signed.', idResponse.message, 'Signed Id should return already signed message.');
    }


    @IsTest
    static void getAgreementShouldReturnExpiredMessage() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'expired-token', System.now().addDays(-1));
        Test.startTest();
        ClientAgreementDTO.PublicAgreementResponse tokenResponse = ClientAgreementPublicController.getAgreementByToken('expired-token');
        ClientAgreementDTO.PublicAgreementResponse idResponse = ClientAgreementPublicController.getAgreementById(agreementRecord.Id);

        Test.stopTest();
        System.assertEquals(false, tokenResponse.valid, 'Expired agreement should not be valid by token.');
        System.assertEquals('This signing link has expired.', tokenResponse.message, 'Expired token should return expired message.');
        System.assertEquals(false, idResponse.valid, 'Expired agreement should not be valid by Id.');
        System.assertEquals('This signing link has expired.', idResponse.message, 'Expired Id should return expired message.');
    }


    /*
     * ============================================================
     * EXISTING SIGNATURE SUBMISSION TEST
     * ============================================================
     */
    @IsTest
    static void submitSignatureShouldCreateSubmissionChunksAndPublishEvent() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'submit-token', System.now().addDays(2));
        String signedPdfBase64 = buildLargeString(210000);
        Test.startTest();
        ClientAgreementPublicController.submitSignature(agreementRecord.Id, SIGNATURE_DATA, SIGNED_HTML, signedPdfBase64);
        Test.stopTest();

        List<Client_Agreement_Submission__c> submissions = [SELECT Id, Client_Agreement__c, Signature_Base64__c, Signed_Agreement_HTML__c, Status__c FROM Client_Agreement_Submission__c WHERE Client_Agreement__c = :agreementRecord.Id];

        System.assertEquals(1, submissions.size(), 'One submission should be created.');
        System.assertEquals(agreementRecord.Id, submissions[0].Client_Agreement__c, 'Submission should be linked to agreement.');
        System.assertNotEquals(null, submissions[0].Status__c, 'Submission status should be populated.');
        System.assertEquals(SIGNATURE_DATA, submissions[0].Signature_Base64__c, 'Signature should be saved on submission.');
        System.assertEquals(SIGNED_HTML, submissions[0].Signed_Agreement_HTML__c, 'Signed HTML should be saved on submission.');
        
        List<Client_Agreement_Submission_Chunk__c> chunks = [
            SELECT Id, Submission_Id__c, Sequence__c, Chunk_Data__c FROM Client_Agreement_Submission_Chunk__c
            WHERE Submission_Id__c =
                :String.valueOf(
                    submissions[0].Id
                )
            ORDER BY Sequence__c ASC
        ];

        System.assertEquals(3, chunks.size(), 'Large PDF base64 should be split into three chunks.');
        System.assertEquals(1, Integer.valueOf(chunks[0].Sequence__c), 'First chunk sequence should be 1.');
        System.assertEquals(100000, chunks[0].Chunk_Data__c.length(), 'First chunk should match configured chunk size.');
    }


    /*
     * ============================================================
     * EXISTING SIGNATURE VALIDATION TESTS
     * ============================================================
     */
    @IsTest
    static void submitSignatureShouldThrowForMissingAgreementId() {

        SubmitParams params = createDefaultSubmitParams();
        Test.startTest();
        Boolean exceptionThrown = submitShouldThrow(params);
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Missing agreement Id should throw handled exception.');
    }


    @IsTest
    static void submitSignatureShouldThrowForDeletedAgreement() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'deleted-submit-token', System.now().addDays(2));
        Id deletedAgreementId = agreementRecord.Id;
        delete agreementRecord;
        SubmitParams params = createDefaultSubmitParams();
        params.agreementId = deletedAgreementId;
        Test.startTest();
        Boolean exceptionThrown = submitShouldThrow(params);
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Deleted agreement should throw handled exception.');
    }


    @IsTest
    static void submitSignatureShouldThrowForMissingSignature() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'missing-signature-token', System.now().addDays(2));
        SubmitParams params = createDefaultSubmitParams();
        params.agreementId = agreementRecord.Id;
        params.signatureBase64 = '';
        Test.startTest();
        Boolean exceptionThrown = submitShouldThrow(params);
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Missing signature should throw handled exception.');
    }


    @IsTest
    static void submitSignatureShouldThrowForMissingHtml() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'missing-html-token', System.now().addDays(2));
        SubmitParams params = createDefaultSubmitParams();
        params.agreementId = agreementRecord.Id;
        params.signedAgreementHtml = '';
        Test.startTest();
        Boolean exceptionThrown = submitShouldThrow(params);
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Missing signed HTML should throw handled exception.');
    }


    @IsTest
    static void submitSignatureShouldThrowForMissingPdf() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'missing-pdf-token', System.now().addDays(2));
        SubmitParams params = createDefaultSubmitParams();
        params.agreementId = agreementRecord.Id;
        params.signedPdfBase64 = '';
        Test.startTest();
        Boolean exceptionThrown = submitShouldThrow(params);
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Missing signed PDF should throw handled exception.');
    }


    @IsTest
    static void submitSignatureShouldThrowForSignedAgreement() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED, 'signed-submit-token', System.now().addDays(2));
        SubmitParams params = createDefaultSubmitParams();
        params.agreementId = agreementRecord.Id;
        Test.startTest();
        Boolean exceptionThrown = submitShouldThrow(params);
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Already signed agreement should throw handled exception.');
    }


    @IsTest
    static void submitSignatureShouldThrowForExpiredAgreement() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT, 'expired-submit-token', System.now().addDays(-1));
        SubmitParams params = createDefaultSubmitParams();
        params.agreementId = agreementRecord.Id;
        Test.startTest();
        Boolean exceptionThrown = submitShouldThrow(params);
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Expired agreement should throw handled exception.');
    }


    /*
     * ============================================================
     * EXISTING HELPERS
     * ============================================================
     */
    private static Boolean submitShouldThrow(SubmitParams params) {

        Boolean exceptionThrown =
            false;

        try {

            ClientAgreementPublicController.submitSignature(params.agreementId, params.signatureBase64, params.signedAgreementHtml, params.signedPdfBase64);

        } catch (
            AuraHandledException exceptionRecord
        ) {

            exceptionThrown =
                true;

            System.assertNotEquals(
                null,
                exceptionRecord,
                'AuraHandledException should be thrown.'
            );
        }

        return exceptionThrown;
    }


    private static SubmitParams createDefaultSubmitParams() {

        SubmitParams params = new SubmitParams();
        params.agreementId = null;
        params.signatureBase64 = 'sig';
        params.signedAgreementHtml = '<p>html</p>';
        params.signedPdfBase64 = 'pdf';
        return params;
    }


    /*
     * ============================================================
     * EXISTING AGREEMENT CREATION
     *
     * TestDataUtility-based Opportunity creation remains unchanged.
     * ============================================================
     */
    private static Client_Agreement__c createAgreement(String statusValue, String tokenValue, Datetime tokenExpiry) {

        Opportunity opportunityRecord = createAreliaOpportunity();
        Client_Agreement__c agreementRecord = new Client_Agreement__c();
        agreementRecord.Opportunity__c = opportunityRecord.Id;
        agreementRecord.Status__c = statusValue;
        agreementRecord.Agreement_HTML__c = AGREEMENT_HTML;
        agreementRecord.Token__c = tokenValue;
        agreementRecord.Token_Expiry__c = tokenExpiry;
        insert agreementRecord;
        return agreementRecord;
    }


    /*
     * ============================================================
     * IMPORTANT:
     * TESTDATAUTILITY IS PRESERVED.
     * ============================================================
     */
    private static Opportunity createAreliaOpportunity() {

        Account accountRecord = TestDataUtility.createAccount(ACCOUNT_NAME);
        User supervisorUser = getSupervisorUser();
        Opportunity opportunityRecord = TestDataUtility.createOpportunity(OPPORTUNITY_NAME, supervisorUser.Id);
        opportunityRecord.AccountId = accountRecord.Id;
        opportunityRecord.Email__c = CLIENT_EMAIL;
        update opportunityRecord;
        System.assertEquals(AreliaUtility.getAreliaOpportunityRecordTypeId(), opportunityRecord.RecordTypeId, 'Opportunity should keep Arelia Record Type from TestDataUtility.');
        return opportunityRecord;
    }


    private static User getSupervisorUser() {

        return [SELECT Id FROM User WHERE Alias = :SUPERVISOR_ALIAS LIMIT 1];
    }


    private static String buildLargeString(Integer targetLength) {

        String seedValue = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

        String result = '';

        while (
            result.length() <
            targetLength
        ) {

            result +=
                seedValue;
        }

        return result.left(
            targetLength
        );
    }


    /*
     * ============================================================
     * NEW HELPER:
     *
     * Creates Salesforce Files directly against the Opportunity
     * for Agreement Preview supporting-image tests.
     * ============================================================
     */
    private static ContentVersion createContentVersion(String title, String pathOnClient, Blob versionData, Id firstPublishLocationId) {

        ContentVersion contentVersion = new ContentVersion();
        contentVersion.Title = title;
        contentVersion.PathOnClient = pathOnClient;
        contentVersion.VersionData = versionData;
        contentVersion.FirstPublishLocationId = firstPublishLocationId;
        contentVersion.IsMajorVersion = true;
        insert contentVersion;

        /*
         * Re-query so ContentDocumentId is populated.
         */
        return [SELECT Id, ContentDocumentId, Title, FileExtension, FileType FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1];
    }


    /*
     * ============================================================
     * NEW HELPER:
     *
     * Used only to verify whether an image is present in the
     * supportingFiles returned by the public controller.
     * ============================================================
     */
    private static Boolean containsSupportingFile(List<ClientAgreementDTO.SupportingFileDTO> files, String expectedFileName) {

        if (
            files == null ||
            files.isEmpty()
        ) {
            return false;
        }

        for (
            ClientAgreementDTO.SupportingFileDTO fileDto :
            files
        ) {

            if (
                fileDto != null &&
                fileDto.fileName ==
                    expectedFileName
            ) {
                return true;
            }
        }

        return false;
    }
}