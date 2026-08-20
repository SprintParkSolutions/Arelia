/**
 * @description Test class for ClientAgreementSignedPdfJob.
 * Covers signed PDF generation, data URI PDF handling, skipped conditions,
 * invalid PDF handling, supporting file handling, supervisor email failure,
 * client signed-agreement email functionality, client-name merge data,
 * and client email failure isolation.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc,PMD.TooManyMethods')
private class ClientAgreementSignedPdfJobTest {

    private static final String SUPERVISOR_ALIAS = 'sigpdf';

    private static final String CLIENT_EMAIL =
        'client@example.com';

    /*
     * Added because ClientAgreementSignedPdfJob now uses
     * Opportunity.Lead_Name__c for {{CLIENT_NAME}}.
     */
    private static final String CLIENT_NAME = 'David K';

    private static final String ACCOUNT_NAME = 'Signed PDF Account';

    private static final String OPPORTUNITY_NAME = 'Signed PDF Opportunity';

    private static final String STATUS_SIGNED = 'Signed';

    private static final String STATUS_SENT = 'Sent';

    private static final String AGREEMENT_HTML =
        '<p>Agreement Body</p>';

    private static final String VALID_PDF_BODY =
        '%PDF-1.4 valid signed pdf content';

    private static final String DATA_URI_PDF_BODY =
        '%PDF-1.4 signed pdf with data uri';

    private static final String SUPPORTING_FILE_BODY =
        'Supporting file test content';

    /*
     * ============================================================
     * TEST SETUP
     * ============================================================
     */
    @TestSetup
    static void setupData() {

        TestDataUtility.createSupervisorUser(
            SUPERVISOR_ALIAS
        );

        /*
         * Existing supervisor email template.
         */
        createSupervisorEmailTemplateIfPossible();

        /*
         * NEW:
         * Client signed-agreement email template.
         *
         * Required because ClientAgreementSignedPdfJob now
         * sends the completed signed agreement to the client.
         */
        createClientSignedAgreementEmailTemplateIfPossible();
    }

    /*
     * ============================================================
     * MAIN SUCCESS TEST
     *
     * This covers:
     * - Signed PDF creation
     * - Signed_File_Id__c update
     * - Supporting file processing
     * - Supervisor email path
     * - Client email path
     * - CLIENT_NAME merge-value preparation
     * - SIGNED_DATE merge-value preparation
     * ============================================================
     */
    @IsTest
    static void executeShouldSaveSignedPdfAndUpdateAgreement() {

        Client_Agreement__c agreementRecord = createAgreement(STATUS_SIGNED);

        /*
         * Valid supporting PDF.
         * Should continue to be available for the existing
         * supervisor email functionality.
         */
        createFileLinkedToAgreement(
            agreementRecord.Id,
            'Supporting PDF',
            'pdf'
        );

        /*
         * Existing generated-agreement files must continue
         * to be ignored as supporting attachments.
         */
        createFileLinkedToAgreement(
            agreementRecord.Id,
            'Client_Agreement_Already_Generated',
            'pdf'
        );

        /*
         * Unsupported TXT file must continue to be ignored.
         */
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

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        /*
         * Most important functional assertion:
         * signed PDF must still be stored.
         */
        System.assertNotEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should be populated.'
        );

        ContentVersion signedVersion =
            getContentVersionById(
                updatedAgreement.Signed_File_Id__c
            );

        System.assert(
            signedVersion.Title.contains(
                'Client_Agreement_'
            ),
            'Signed PDF title should follow expected naming.'
        );

        System.assert(
            signedVersion.PathOnClient.endsWith(
                '_Signed.pdf'
            ),
            'Signed PDF file name should end with _Signed.pdf.'
        );

        /*
         * Confirm Opportunity remains correctly associated.
         */
        System.assertEquals(
            agreementRecord.Opportunity__c,
            updatedAgreement.Opportunity__c,
            'Agreement should remain linked to the original Opportunity.'
        );
    }

    /*
     * ============================================================
     * CLIENT NAME TEST DATA
     *
     * Production code uses Opportunity.Lead_Name__c for:
     *
     * {{CLIENT_NAME}}
     *
     * This verifies that the test data contains that value.
     * ============================================================
     */
    @IsTest
    static void opportunityShouldContainClientNameForSignedEmail() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        Opportunity opportunityRecord = [
            SELECT Id,
                   Email__c,
                   Lead_Name__c
            FROM Opportunity
            WHERE Id = :agreementRecord.Opportunity__c
            LIMIT 1
        ];

        System.assertEquals(
            CLIENT_NAME,
            opportunityRecord.Lead_Name__c,
            'Opportunity should contain the client name used by the signed-agreement client email.'
        );

        System.assertEquals(
            CLIENT_EMAIL,
            opportunityRecord.Email__c,
            'Opportunity should contain the client email used for signed PDF delivery.'
        );
    }

    /*
     * ============================================================
     * DATA URI PDF TEST
     * ============================================================
     */
    @IsTest
    static void executeShouldHandleDataUriPdfBase64() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        String signedPdfBase64 =
            'data:application/pdf;base64,' +
            EncodingUtil.base64Encode(
                Blob.valueOf(
                    DATA_URI_PDF_BODY
                )
            );

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                signedPdfBase64
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        System.assertNotEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file should be created from data URI Base64.'
        );
    }

    /*
     * ============================================================
     * NULL AGREEMENT ID
     * ============================================================
     */
    @IsTest
    static void executeShouldSkipWhenAgreementIdIsNull() {

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(null)
        );

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

    /*
     * ============================================================
     * AGREEMENT NOT SIGNED
     * ============================================================
     */
    @IsTest
    static void executeShouldSkipWhenAgreementIsNotSigned() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SENT);

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                validPdfBase64()
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Unsigned agreement should be skipped.'
        );
    }

    /*
     * ============================================================
     * NULL PDF - TWO ARGUMENT CONSTRUCTOR
     * ============================================================
     */
    @IsTest
    static void executeShouldSkipWhenPdfBase64IsBlankUsingTwoArgumentConstructor() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                null
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when PDF Base64 is null.'
        );
    }

    /*
     * ============================================================
     * NULL PDF - ONE ARGUMENT CONSTRUCTOR
     * ============================================================
     */
    @IsTest
    static void executeShouldSkipWhenPdfBase64IsBlankUsingOneArgumentConstructor() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when one-argument constructor is used.'
        );
    }

    /*
     * ============================================================
     * INVALID BASE64
     * ============================================================
     */
    @IsTest
    static void executeShouldSkipWhenPdfBase64IsInvalid() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                'invalid-base64'
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when Base64 is invalid.'
        );
    }

    /*
     * ============================================================
     * DECODED BLOB IS NOT A PDF
     * ============================================================
     */
    @IsTest
    static void executeShouldSkipWhenBlobIsNotPdf() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        String nonPdfBase64 =
            EncodingUtil.base64Encode(
                Blob.valueOf(
                    'This is not a PDF file'
                )
            );

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                nonPdfBase64
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        System.assertEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should remain blank when decoded blob is not a PDF.'
        );
    }

    /*
     * ============================================================
     * EXISTING SUPERVISOR EMAIL FAILURE TEST
     *
     * Critical:
     * Email failure must never prevent signed PDF persistence.
     * ============================================================
     */
    @IsTest
    static void executeShouldSaveSignedPdfEvenWhenSupervisorEmailFails() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        Opportunity opportunityRecord = [
            SELECT Id,
                   Supervisor_User__c
            FROM Opportunity
            WHERE Id = :agreementRecord.Opportunity__c
            LIMIT 1
        ];

        /*
         * Removing supervisor forces the existing supervisor
         * notification path to fail.
         */
        opportunityRecord.Supervisor_User__c =
            null;

        update opportunityRecord;

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                validPdfBase64()
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        /*
         * Existing important behavior remains unchanged.
         */
        System.assertNotEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file should still be saved even when supervisor email sending fails.'
        );
    }

    /*
     * ============================================================
     * NEW CLIENT EMAIL FAILURE TEST
     *
     * Verifies that failure of the new client notification
     * does NOT interfere with:
     *
     * - PDF generation
     * - Salesforce File creation
     * - Signed_File_Id__c
     * - Existing workflow
     *
     * This protects the new functionality from affecting
     * existing functionality.
     * ============================================================
     */
    @IsTest
    static void executeShouldSaveSignedPdfEvenWhenClientEmailFails() {

        Client_Agreement__c agreementRecord =
            createAgreement(STATUS_SIGNED);

        Opportunity opportunityRecord = [
            SELECT Id,
                   Email__c,
                   Supervisor_User__c
            FROM Opportunity
            WHERE Id = :agreementRecord.Opportunity__c
            LIMIT 1
        ];

        /*
         * Deliberately remove only the client email.
         *
         * The production method
         * sendClientSignedAgreementEmail()
         * should fail internally and its surrounding try/catch
         * should prevent that failure from affecting PDF storage.
         */
        opportunityRecord.Email__c =
            null;

        update opportunityRecord;

        Test.startTest();

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreementRecord.Id,
                validPdfBase64()
            )
        );

        Test.stopTest();

        Client_Agreement__c updatedAgreement =
            getAgreementById(
                agreementRecord.Id
            );

        /*
         * This is the important regression assertion.
         */
        System.assertNotEquals(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed PDF should still be saved even when the client email cannot be sent.'
        );

        ContentVersion signedVersion =
            getContentVersionById(
                updatedAgreement.Signed_File_Id__c
            );

        System.assert(
            signedVersion.PathOnClient.endsWith(
                '_Signed.pdf'
            ),
            'Signed PDF should remain valid even when client email sending fails.'
        );
    }

    /*
     * ============================================================
     * TEST DATA - CLIENT AGREEMENT
     * ============================================================
     */
    private static Client_Agreement__c createAgreement(
        String statusValue
    ) {

        Opportunity opportunityRecord =
            createAreliaOpportunity();

        Client_Agreement__c agreementRecord =
            new Client_Agreement__c();

        agreementRecord.Opportunity__c =
            opportunityRecord.Id;

        agreementRecord.Status__c =
            statusValue;

        agreementRecord.Agreement_HTML__c =
            AGREEMENT_HTML;

        /*
         * Populate Signed_Date__c for signed agreements so the
         * production getSignedDateText() success branch is covered.
         */
        if (statusValue == STATUS_SIGNED) {
            agreementRecord.Signed_Date__c =
                System.now();
        }

        insert agreementRecord;

        return agreementRecord;
    }

    /*
     * ============================================================
     * TEST DATA - ARELIA OPPORTUNITY
     * ============================================================
     */
    private static Opportunity createAreliaOpportunity() {

        Account accountRecord =
            TestDataUtility.createAccount(
                ACCOUNT_NAME
            );

        User supervisorUser =
            getSupervisorUser();

        Opportunity opportunityRecord =
            TestDataUtility.createOpportunity(
                OPPORTUNITY_NAME,
                supervisorUser.Id
            );

        opportunityRecord.AccountId =
            accountRecord.Id;

        /*
         * Existing client email.
         * This is where the signed Client Agreement PDF is sent.
         */
        opportunityRecord.Email__c =
            CLIENT_EMAIL;

        /*
         * NEW:
         * Required by the personalized signed-agreement email.
         *
         * Production email uses this value for:
         * {{CLIENT_NAME}}
         */
        opportunityRecord.Lead_Name__c =
            CLIENT_NAME;

        update opportunityRecord;

        System.assertEquals(
            AreliaUtility.getAreliaOpportunityRecordTypeId(),
            opportunityRecord.RecordTypeId,
            'Opportunity should keep Arelia Record Type from TestDataUtility.'
        );

        return opportunityRecord;
    }

    /*
     * ============================================================
     * GET SUPERVISOR
     * ============================================================
     */
    private static User getSupervisorUser() {

        return [
            SELECT Id
            FROM User
            WHERE Alias = :SUPERVISOR_ALIAS
            LIMIT 1
        ];
    }

    /*
     * ============================================================
     * GET AGREEMENT
     * ============================================================
     */
    private static Client_Agreement__c getAgreementById(Id agreementId) {

        return [
            SELECT Id,
                   Opportunity__c,
                   Signed_File_Id__c,
                   Signed_Date__c,
                   Status__c
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];
    }

    /*
     * ============================================================
     * GET CONTENT VERSION
     * ============================================================
     */
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

    /*
     * ============================================================
     * VALID PDF BASE64
     * ============================================================
     */
    private static String validPdfBase64() {

        return EncodingUtil.base64Encode(
            Blob.valueOf(
                VALID_PDF_BODY
            )
        );
    }

    /*
     * ============================================================
     * SUPPORTING FILE CREATION
     * ============================================================
     */
    private static void createFileLinkedToAgreement(Id agreementId, String fileTitle, String fileExtension) {

        ContentVersion contentVersionRecord = new ContentVersion();

        contentVersionRecord.Title = fileTitle;

        contentVersionRecord.PathOnClient =
            fileTitle +
            '.' +
            fileExtension;

        contentVersionRecord.VersionData =
            Blob.valueOf(
                SUPPORTING_FILE_BODY
            );

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

    /*
     * ============================================================
     * EXISTING SUPERVISOR EMAIL TEMPLATE
     * ============================================================
     */
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

        System.runAs(
            new User(
                Id = UserInfo.getUserId()
            )
        ) {

            TestDataUtility.createSpecificEmailTemplate(
                templateDeveloperName,
                templateDeveloperName,
                'Signed Agreement {{OPPORTUNITY_NAME}}',
                '<html><body>{{CLIENT_EMAIL}}</body></html>'
            );
        }
    }

    /*
     * ============================================================
     * NEW CLIENT SIGNED AGREEMENT EMAIL TEMPLATE
     *
     * Production Custom Label:
     *
     * Client_Agreement_Signed_Client_Email
     *
     * Its value should contain the DeveloperName of the
     * Lightning Email Template used for the client.
     * ============================================================
     */
    private static void createClientSignedAgreementEmailTemplateIfPossible() {

        String templateDeveloperName =
            System.Label.Client_Agreement_Signed_Client_Email;

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

        System.runAs(
            new User(
                Id = UserInfo.getUserId()
            )
        ) {

            TestDataUtility.createSpecificEmailTemplate(
                templateDeveloperName,
                templateDeveloperName,

                /*
                 * Same merge tokens supported by the
                 * production ClientAgreementEmailService.
                 */
                'Signed Client Agreement - {{OPPORTUNITY_NAME}}',

                '<html><body>' +
                '<p>Dear {{CLIENT_NAME}},</p>' +
                '<p>Thank you for completing the client agreement for ' +
                '<strong>{{OPPORTUNITY_NAME}}</strong>.</p>' +
                '<p>Please find attached a copy of your signed Client Agreement.</p>' +
                '<p>Signed on <strong>{{SIGNED_DATE}}</strong>.</p>' +
                '</body></html>'
            );
        }
    }
}