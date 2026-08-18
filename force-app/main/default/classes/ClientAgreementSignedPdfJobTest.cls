/**
 * @description Test class for ClientAgreementSignedPdfJob.
 * Covers signed PDF generation, data URI PDF handling, skipped conditions,
 * invalid PDF handling, supporting file handling, and supervisor email failure path.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc,PMD.TooManyMethods')
private class ClientAgreementSignedPdfJobTest {
    private static final String SUPERVISOR_ALIAS = 'sigpdf';
    private static final String CLIENT_EMAIL = 'client@example.com';

    private static final String ACCOUNT_NAME = 'Signed PDF Account';
    private static final String OPPORTUNITY_NAME = 'Signed PDF Opportunity';

    private static final String STATUS_SIGNED = 'Signed';
    private static final String STATUS_SENT = 'Sent';

    private static final String AGREEMENT_HTML = '<p>Agreement Body</p>';
    private static final String VALID_PDF_BODY = '%PDF-1.4 valid signed pdf content';
    private static final String DATA_URI_PDF_BODY = '%PDF-1.4 signed pdf with data uri';
    private static final String SUPPORTING_FILE_BODY = 'Supporting file test content';

    @TestSetup
    static void setupData() {
        TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);
        createSupervisorEmailTemplateIfPossible();
    }

    @IsTest
    static void executeShouldSaveSignedPdfAndUpdateAgreement() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        createFileLinkedToAgreement(
            agreementRecord.Id,
            'Supporting PDF',
            'pdf'
        );

        createFileLinkedToAgreement(
            agreementRecord.Id,
            'Client_Agreement_Already_Generated',
            'pdf'
        );

        createFileLinkedToAgreement(
            agreementRecord.Id,
            'Text Notes',
            'txt'
        );

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                validPdfBase64()
            )
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertNotEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should be populated.'
        );

        ContentVersion signedVersion = getContentVersionById(
            updatedAgreement.Signed_File_Id__c
        );

        System.assert(
            signedVersion.Title.contains('Client_Agreement_'),
            'Signed PDF title should follow expected naming.'
        );
        System.assert(
            signedVersion.PathOnClient.endsWith('_Signed.pdf'),
            'Signed PDF file name should end with _Signed.pdf.'
        );
    }

    @IsTest
    static void executeShouldHandleDataUriPdfBase64() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        String signedPdfBase64 =
            'data:application/pdf;base64,' +
            EncodingUtil.base64Encode(
                Blob.valueOf(DATA_URI_PDF_BODY)
            );

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                signedPdfBase64
            )
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertNotEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file should be created from data URI Base64.'
        );
    }

    @IsTest
    static void executeShouldSkipWhenAgreementIdIsNull() {
        Test.startTest();
        System.enqueueJob(new ClientAgreementSignedPdfJob(null));
        Test.stopTest();

        Integer generatedFileCount = [
            SELECT COUNT()
            FROM ContentVersion
            WHERE Title LIKE 'Client_Agreement_%'
        ];

        System.assertEquals(
            0,
            generatedFileCount,
            'No signed file should be created when agreement Id is null.'
        );
    }

    @IsTest
    static void executeShouldSkipWhenAgreementIsNotSigned() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SENT);

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                validPdfBase64()
            )
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Unsigned agreement should be skipped.'
        );
    }

    @IsTest
    static void executeShouldSkipWhenPdfBase64IsBlankUsingTwoArgumentConstructor() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                null
            )
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when PDF Base64 is null.'
        );
    }

    @IsTest
    static void executeShouldSkipWhenPdfBase64IsBlankUsingOneArgumentConstructor() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(agreementRecord.Id)
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when one-argument constructor is used.'
        );
    }

    @IsTest
    static void executeShouldSkipWhenPdfBase64IsInvalid() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                'invalid-base64'
            )
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when Base64 is invalid.'
        );
    }

    @IsTest
    static void executeShouldSkipWhenBlobIsNotPdf() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        String nonPdfBase64 = EncodingUtil.base64Encode(
            Blob.valueOf('This is not a PDF file')
        );

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                nonPdfBase64
            )
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when decoded blob is not a PDF.'
        );
    }

    @IsTest
    static void executeShouldSaveSignedPdfEvenWhenSupervisorEmailFails() {
        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        Opportunity opportunityRecord = [
            SELECT Id, Supervisor_User__c
            FROM Opportunity
            WHERE Id = :agreementRecord.Opportunity__c
            LIMIT 1
        ];

        opportunityRecord.Supervisor_User__c = null;
        update opportunityRecord;

        Test.startTest();
        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                validPdfBase64()
            )
        );
        Test.stopTest();

        Client_Agreement__c updatedAgreement = getAgreementById(agreementRecord.Id);

        System.assertNotEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file should still be saved even when supervisor email sending fails.'
        );
    }

    private static Client_Agreement__c createAgreement(String statusValue) {
        Opportunity opportunityRecord = createAreliaOpportunity();

        Client_Agreement__c agreementRecord = new Client_Agreement__c();
        agreementRecord.Opportunity__c = opportunityRecord.Id;
        agreementRecord.Status__c = statusValue;
        agreementRecord.Agreement_HTML__c = AGREEMENT_HTML;

        insert agreementRecord;

        return agreementRecord;
    }

    private static Opportunity createAreliaOpportunity() {
        Account accountRecord = TestDataUtility.createAccount(ACCOUNT_NAME);
        User supervisorUser = getSupervisorUser();

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

    private static User getSupervisorUser() {
        return [
            SELECT Id
            FROM User
            WHERE Alias = :SUPERVISOR_ALIAS
            LIMIT 1
        ];
    }

    private static Client_Agreement__c getAgreementById(Id agreementId) {
        return [
            SELECT Id,
                   Opportunity__c,
                   Signed_File_Id__c
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];
    }

    private static ContentVersion getContentVersionById(String contentVersionIdValue) {
        return [
            SELECT Id,
                   Title,
                   PathOnClient,
                   ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionIdValue
            LIMIT 1
        ];
    }

    private static String validPdfBase64() {
        return EncodingUtil.base64Encode(
            Blob.valueOf(VALID_PDF_BODY)
        );
    }

    private static void createFileLinkedToAgreement(
        Id agreementId,
        String fileTitle,
        String fileExtension
    ) {
        ContentVersion contentVersionRecord = new ContentVersion();
        contentVersionRecord.Title = fileTitle;
        contentVersionRecord.PathOnClient = fileTitle + '.' + fileExtension;
        contentVersionRecord.VersionData = Blob.valueOf(SUPPORTING_FILE_BODY);
        contentVersionRecord.IsMajorVersion = true;

        insert contentVersionRecord;

        ContentVersion insertedVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionRecord.Id
            LIMIT 1
        ];

        ContentDocumentLink linkRecord = new ContentDocumentLink();
        linkRecord.ContentDocumentId = insertedVersion.ContentDocumentId;
        linkRecord.LinkedEntityId = agreementId;
        linkRecord.ShareType = 'V';
        linkRecord.Visibility = 'AllUsers';

        insert linkRecord;
    }

    private static void createSupervisorEmailTemplateIfPossible() {
        String templateDeveloperName = System.Label.Client_Agreement_Supervisor_Email;

        if (String.isBlank(templateDeveloperName)) {
            return;
        }

        List<EmailTemplate> existingTemplates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :templateDeveloperName
            LIMIT 1
        ];

        if (!existingTemplates.isEmpty()) {
            return;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                templateDeveloperName,
                templateDeveloperName,
                'Signed Agreement {{OPPORTUNITY_NAME}}',
                '<html><body>{{CLIENT_EMAIL}}</body></html>'
            );
        }
    }
}