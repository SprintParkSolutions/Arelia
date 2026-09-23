/**
 * @description Test class for AgreementPdfController.
 * Covers signed agreement PDF loading, signature formatting, HTML sanitization,
 * plain text conversion, blank agreement handling, and missing/invalid page Id scenarios.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc')
private class AgreementPdfControllerTest {
    private static final String CLIENT_EMAIL = 'client@example.com';
    private static final String ACCOUNT_NAME = 'Agreement PDF Test Account';

    private static final String AGREEMENT_STATUS_SIGNED = 'Signed';
    private static final String AGREEMENT_STATUS_SENT = 'Sent';

    private static final String DATA_URI_SIGNATURE = 'data:image/png;base64,ABC123';
    private static final String RAW_SIGNATURE = 'RAW_SIGNATURE_BASE64';
    private static final String RAW_SIGNATURE_DATA_URI = 'data:image/png;base64,RAW_SIGNATURE_BASE64';

    private static final String PDF_FILE_TITLE = 'Agreement PDF File';
    private static final String SIGNED_FILE_TITLE = 'Signed Agreement File';
    private static final String FILE_BODY = 'Agreement file body';

    private class AgreementParams {
        String statusValue;
        String agreementHtml;
        String signatureBase64;
        Datetime signedDate;
    }

    @IsTest
    static void constructorShouldLoadSignedAgreementWithDataUriSignature() {
        AgreementParams params = createAgreementParams();
        params.statusValue = AGREEMENT_STATUS_SIGNED;
        params.agreementHtml = buildAgreementHtml();
        params.signatureBase64 = DATA_URI_SIGNATURE;
        params.signedDate = System.now();

        Client_Agreement__c agreementRecord = createAgreement(params);

        setCurrentPageAgreementId(agreementRecord.Id);

        Test.startTest();
        AgreementPdfController controller = new AgreementPdfController();
        Test.stopTest();

        System.assertNotEquals(
            null,
            controller.agreement,
            'Agreement should be loaded.'
        );
        System.assertNotEquals(
            null,
            controller.opp,
            'Opportunity should be loaded.'
        );
        System.assertEquals(
            'Signed Client Agreement',
            controller.documentTitle,
            'Signed agreement should show signed document title.'
        );
        System.assertEquals(
            true,
            controller.hasSignature,
            'Signed agreement with signature data should show hasSignature as true.'
        );
        System.assertEquals(
            true,
            controller.hasSignatureImage,
            'Signed agreement with signature data should show hasSignatureImage as true.'
        );
        System.assertEquals(
            DATA_URI_SIGNATURE,
            controller.signatureDataUri,
            'Existing data URI signature should remain unchanged.'
        );
        System.assert(
            controller.agreementHtml.contains('<h1>Agreement Title</h1>'),
            'Sanitized HTML should retain allowed content.'
        );
        System.assert(
            !controller.agreementHtml.contains('<script>'),
            'Sanitized HTML should remove script tags.'
        );
        System.assert(
            !controller.agreementHtml.contains('<style>'),
            'Sanitized HTML should remove style tags.'
        );
        System.assert(
            !controller.agreementHtml.contains('<iframe'),
            'Sanitized HTML should remove iframe tags.'
        );
        System.assert(
            !controller.agreementHtml.contains('<object'),
            'Sanitized HTML should remove object tags.'
        );
        System.assert(
            !controller.agreementHtml.contains('<embed'),
            'Sanitized HTML should remove embed tags.'
        );
        System.assert(
            controller.agreementPlainText.contains('Agreement Title'),
            'Plain text should contain heading text.'
        );
        System.assert(
            controller.agreementPlainText.contains('Line one'),
            'Plain text should contain paragraph text.'
        );
        System.assert(
            controller.agreementPlainText.contains('Bullet & Item'),
            'Plain text should decode HTML entities.'
        );
        System.assert(
            controller.agreementPlainText.contains('Client <Name>'),
            'Plain text should decode less-than and greater-than entities.'
        );
        System.assertNotEquals(
            '',
            controller.signedDateText,
            'Signed date text should be populated for signed agreement.'
        );
        System.assertNotEquals(
            '',
            controller.generatedDateText,
            'Generated date text should always be populated.'
        );
    }

    @IsTest
    static void constructorShouldPrefixRawSignatureBase64() {
        AgreementParams params = createAgreementParams();
        params.statusValue = AGREEMENT_STATUS_SIGNED;
        params.agreementHtml = '<p>Simple Agreement</p>';
        params.signatureBase64 = RAW_SIGNATURE;
        params.signedDate = System.now();

        Client_Agreement__c agreementRecord = createAgreement(params);

        setCurrentPageAgreementId(agreementRecord.Id);

        Test.startTest();
        AgreementPdfController controller = new AgreementPdfController();
        Test.stopTest();

        System.assertEquals(
            true,
            controller.hasSignature,
            'Raw base64 signature should still be treated as a valid signature.'
        );
        System.assertEquals(
            true,
            controller.hasSignatureImage,
            'Raw base64 signature should create a signature image data URI.'
        );
        System.assertEquals(
            RAW_SIGNATURE_DATA_URI,
            controller.signatureDataUri,
            'Raw base64 signature should be prefixed with image data URI.'
        );
    }

    @IsTest
    static void constructorShouldHandleBlankAgreementAndNoSignature() {
        AgreementParams params = createAgreementParams();
        params.statusValue = AGREEMENT_STATUS_SENT;
        params.agreementHtml = null;
        params.signatureBase64 = null;
        params.signedDate = null;

        Client_Agreement__c agreementRecord = createAgreement(params);

        setCurrentPageAgreementId(agreementRecord.Id);

        Test.startTest();
        AgreementPdfController controller = new AgreementPdfController();
        Test.stopTest();

        System.assertEquals(
            'Client Agreement',
            controller.documentTitle,
            'Unsigned agreement should show default document title.'
        );
        System.assertEquals(
            false,
            controller.hasSignature,
            'Agreement without signature should not show hasSignature.'
        );
        System.assertEquals(
            false,
            controller.hasSignatureImage,
            'Agreement without signature should not show hasSignatureImage.'
        );
        System.assertEquals(
            null,
            controller.signatureDataUri,
            'Signature data URI should be null when no signature exists.'
        );
        System.assertEquals(
            '<p>No agreement body found.</p>',
            controller.agreementHtml,
            'Blank agreement HTML should use default message.'
        );
        System.assertEquals(
            'No agreement body found.',
            controller.agreementPlainText,
            'Blank agreement plain text should use default message.'
        );
        System.assertEquals(
            '',
            controller.signedDateText,
            'Signed date text should be blank when agreement is not signed.'
        );
    }

    @IsTest
    static void constructorShouldHandleEmptyAgreementHtml() {
        AgreementParams params = createAgreementParams();
        params.statusValue = AGREEMENT_STATUS_SENT;
        params.agreementHtml = '';
        params.signatureBase64 = '';
        params.signedDate = null;

        Client_Agreement__c agreementRecord = createAgreement(params);

        setCurrentPageAgreementId(agreementRecord.Id);

        Test.startTest();
        AgreementPdfController controller = new AgreementPdfController();
        Test.stopTest();

        System.assertEquals(
            '<p>No agreement body found.</p>',
            controller.agreementHtml,
            'Empty agreement HTML should use default message.'
        );
        System.assertEquals(
            'No agreement body found.',
            controller.agreementPlainText,
            'Empty agreement plain text should use default message.'
        );
        System.assertEquals(
            false,
            controller.hasSignature,
            'Blank signature should not be treated as signature.'
        );
    }

    @IsTest
    static void constructorShouldThrowErrorWhenAgreementIdMissing() {
        Test.setCurrentPage(new PageReference('/apex/AgreementPdf'));

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            new AgreementPdfController();
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown when agreement Id is missing.'
        );
    }

    @IsTest
    static void constructorShouldThrowErrorWhenAgreementIdIsInvalidFormat() {
        PageReference pageReference = new PageReference('/apex/AgreementPdf');
        pageReference.getParameters().put('id', 'invalid-id-value');
        Test.setCurrentPage(pageReference);

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            new AgreementPdfController();
        } catch (Exception exceptionRecord) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown when agreement Id format is invalid.'
        );
    }

    private static AgreementParams createAgreementParams() {
        return new AgreementParams();
    }

    private static Client_Agreement__c createAgreement(AgreementParams params) {
        Opportunity opportunityRecord = createOpportunity();

        ContentVersion pdfFile = TestDataUtility.createContentVersion(
            PDF_FILE_TITLE,
            FILE_BODY
        );

        ContentVersion signedFile = TestDataUtility.createContentVersion(
            SIGNED_FILE_TITLE,
            FILE_BODY
        );

        Client_Agreement__c agreementRecord = new Client_Agreement__c();
        agreementRecord.Opportunity__c = opportunityRecord.Id;
        agreementRecord.Status__c = params.statusValue;
        agreementRecord.Agreement_HTML__c = params.agreementHtml;
        agreementRecord.Signature_Base64__c = params.signatureBase64;
        agreementRecord.Signed_Date__c = params.signedDate;
        agreementRecord.PDF_File_Id__c = String.valueOf(pdfFile.Id);
        agreementRecord.Signed_File_Id__c = String.valueOf(signedFile.Id);

        insert agreementRecord;

        return agreementRecord;
    }

    private static Opportunity createOpportunity() {
        Account accountRecord = TestDataUtility.createAccount(ACCOUNT_NAME);

        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            'Test Agreement PDF Opportunity',
            UserInfo.getUserId()
        );

        opportunityRecord.AccountId = accountRecord.Id;
        opportunityRecord.Email__c = CLIENT_EMAIL;
        update opportunityRecord;

        System.assertEquals(
            AreliaUtility.getAreliaOpportunityRecordTypeId(),
            opportunityRecord.RecordTypeId,
            'Opportunity should keep the Arelia Record Type from TestDataUtility.'
        );

        return opportunityRecord;
    }

    private static void setCurrentPageAgreementId(Id agreementId) {
        PageReference pageReference = new PageReference('/apex/AgreementPdf');
        pageReference.getParameters().put('id', String.valueOf(agreementId));
        Test.setCurrentPage(pageReference);
    }

    private static String buildAgreementHtml() {
        return ''
            + '<h1>Agreement Title</h1>'
            + '<p>Line one&nbsp;&amp;&nbsp;line two.</p>'
            + '<div>Client &lt;Name&gt;</div>'
            + '<h2>Terms</h2>'
            + '<ul><li>Bullet &amp; Item</li></ul>'
            + '<br/>'
            + '<script>alert("remove");</script>'
            + '<style>.remove{color:red;}</style>'
            + '<iframe src="test"></iframe>'
            + '<object></object>'
            + '<embed src="test">';
    }
}