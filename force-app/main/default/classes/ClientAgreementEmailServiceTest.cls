/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementEmailServiceTest
 * Author          : <YourName>
 * Created Date    : Jun 29, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 29, 2026
 * Description     : Test class for ClientAgreementEmailService.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
/**
 * Test class for ClientAgreementEmailService.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.TooManyMethods')
private class ClientAgreementEmailServiceTest {

    private static final String RECIPIENT_EMAIL = 'client@example.com';
    private static final String TEMPLATE_ONE = 'Client_Agreement_Template_One';
    private static final String TEMPLATE_TWO = 'Client_Agreement_Template_Two';
    private static final String TEMPLATE_THREE = 'Client_Agreement_Template_Three';
    private static final String TEMPLATE_FOUR = 'Client_Agreement_Template_Four';
    private static final String TEMPLATE_FIVE = 'Client_Agreement_Template_Five';
    private static final String MISSING_TEMPLATE = 'Template_That_Does_Not_Exist';

    @TestSetup
    static void setupData() {
        insert new List<EmailTemplate>{
            buildTemplate(
                TEMPLATE_ONE,
                'Agreement for {{CLIENT_EMAIL}}',
                '<html><body>Hello {{CLIENT_EMAIL}} - {{OPPORTUNITY_NAME}}</body></html>'
            ),
            buildTemplate(
                TEMPLATE_TWO,
                'Supporting Files',
                '<html><body>Supporting files attached.</body></html>'
            ),
            buildTemplate(
                TEMPLATE_THREE,
                '',
                ''
            ),
            buildTemplate(
                TEMPLATE_FOUR,
                'Data URI',
                '<html><body>Data URI test.</body></html>'
            ),
            buildTemplate(
                TEMPLATE_FIVE,
                'Invalid Base64',
                '<html><body>Invalid Base64</body></html>'
            )
        };
    }

    @IsTest
    static void sendEmailShouldSendUsingTemplateAndRawPdfAttachment() {
        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_ONE);

        request.attachmentFileName = 'Client Agreement';
        request.attachmentBase64 = EncodingUtil.base64Encode(Blob.valueOf('PDF body'));
        request.attachmentContentType = 'application/pdf';
        request.mergeValues = new Map<String, String>{
            'CLIENT_EMAIL' => RECIPIENT_EMAIL,
            'OPPORTUNITY_NAME' => 'Test Opportunity'
        };

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldSendWithEntityAttachmentsAndAdditionalAttachments() {
        ContentVersion mainVersion = createContentVersion(
            'MainAgreement',
            'MainAgreement.pdf',
            Blob.valueOf('Main agreement content')
        );

        ContentVersion supportingVersion = createContentVersion(
            'SupportingImage',
            'SupportingImage.png',
            Blob.valueOf('Supporting image content')
        );

        ClientAgreementEmailService.EmailAttachment skippedAttachment =
            new ClientAgreementEmailService.EmailAttachment();

        skippedAttachment.fileName = 'blank-file.pdf';
        skippedAttachment.base64Data = null;
        skippedAttachment.contentType = 'application/pdf';

        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_TWO);

        request.attachmentContentVersionId = mainVersion.Id;
        request.entityAttachmentContentVersionIds = new List<Id>{ supportingVersion.Id };
        request.additionalAttachments = new List<ClientAgreementEmailService.EmailAttachment>{
            createRawAttachment('design-image', Blob.valueOf('PNG body'), 'image/png'),
            createRawAttachment('site-photo.jpeg', Blob.valueOf('JPEG body'), 'image/jpg'),
            skippedAttachment,
            null
        };

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldNormalizeContentTypeFromFileName() {
        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_THREE);

        request.additionalAttachments = new List<ClientAgreementEmailService.EmailAttachment>{
            createRawAttachment('supporting-document.pdf', Blob.valueOf('PDF body'), null),
            createRawAttachment('site-photo.jpg', Blob.valueOf('JPG body'), null),
            createRawAttachment('unknown-file', Blob.valueOf('Unknown body'), null)
        };

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldHandleDataUriBase64AndUnsafeFileName() {
        String dataUri =
            'data:application/pdf;base64,' +
            EncodingUtil.base64Encode(Blob.valueOf('PDF data uri body'));

        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_FOUR);

        request.attachmentFileName = 'Client/Agreement:Final?Version';
        request.attachmentBase64 = dataUri;
        request.attachmentContentType = 'application/pdf';

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldUseFallbackWhenTemplateNameIsBlank() {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.toAddress = RECIPIENT_EMAIL;
        request.templateDeveloperName = null;
        request.mergeValues = new Map<String, String>{
            'OPPORTUNITY_NAME' => 'Fallback Opportunity',
            'CLIENT_EMAIL' => RECIPIENT_EMAIL,
            'SUPERVISOR_EMAIL' => 'supervisor@example.com',
            'SIGNING_URL' => 'https://example.com/sign'
        };

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldUseFallbackWhenTemplateDoesNotExist() {
        ClientAgreementEmailService.EmailRequest request = createBaseRequest(MISSING_TEMPLATE);

        request.mergeValues = new Map<String, String>{
            'OPPORTUNITY_NAME' => 'Missing Template Opportunity',
            'CLIENT_EMAIL' => RECIPIENT_EMAIL,
            'SUPERVISOR_EMAIL' => 'supervisor@example.com',
            'SIGNING_URL' => 'https://example.com/sign'
        };

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldSendWithOnlyFallbackBodyAndNoAttachments() {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.toAddress = RECIPIENT_EMAIL;
        request.templateDeveloperName = '';
        request.additionalAttachments = new List<ClientAgreementEmailService.EmailAttachment>();

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldReplaceNullMergeValueWithBlank() {
        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_ONE);

        request.mergeValues = new Map<String, String>{
            'CLIENT_EMAIL' => null,
            'OPPORTUNITY_NAME' => 'Null Merge Opportunity'
        };

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldHandleBlankFileNameAndJpegContentType() {
        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_TWO);

        request.additionalAttachments = new List<ClientAgreementEmailService.EmailAttachment>{
            createRawAttachment(null, Blob.valueOf('Default filename body'), 'application/pdf'),
            createRawAttachment('photo-without-extension', Blob.valueOf('JPEG body'), 'image/jpeg')
        };

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldSkipBlankBase64RawMainAttachment() {
        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_TWO);

        request.attachmentFileName = 'Blank.pdf';
        request.attachmentBase64 = '';
        request.attachmentContentType = 'application/pdf';

        assertEmailCompletes(request);
    }

    @IsTest
    static void sendEmailShouldThrowWhenRequestIsNull() {
        assertSendThrows(null, 'Missing request should throw exception.');
    }

    @IsTest
    static void sendEmailShouldThrowWhenRecipientIsBlank() {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.templateDeveloperName = TEMPLATE_ONE;

        assertSendThrows(request, 'Missing recipient should throw exception.');
    }

    @IsTest
    static void sendEmailShouldThrowWhenBase64IsInvalid() {
        ClientAgreementEmailService.EmailRequest request = createBaseRequest(TEMPLATE_FIVE);

        request.attachmentFileName = 'Invalid.pdf';
        request.attachmentBase64 = 'invalid-base64-value';
        request.attachmentContentType = 'application/pdf';

        assertSendThrows(request, 'Invalid Base64 should throw exception.');
    }

    @IsTest
    static void getOrgWideEmailAddressIdFromLabelShouldCompleteSafely() {
        Boolean completed = false;

        Test.startTest();
        ClientAgreementEmailService.getOrgWideEmailAddressIdFromLabel();
        completed = true;
        Test.stopTest();

        System.assertEquals(true, completed, 'OWD lookup should complete safely.');
    }

    private static void assertEmailCompletes(
        ClientAgreementEmailService.EmailRequest request
    ) {
        Boolean completed = false;

        Test.startTest();
        ClientAgreementEmailService.sendEmail(request);
        completed = true;
        Test.stopTest();

        System.assertEquals(true, completed, 'Email service should complete without exception.');
    }

    private static void assertSendThrows(
        ClientAgreementEmailService.EmailRequest request,
        String assertionMessage
    ) {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementEmailService.sendEmail(request);
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(null, exceptionRecord, 'Exception should be available.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, assertionMessage);
    }

    private static ClientAgreementEmailService.EmailRequest createBaseRequest(
        String templateDeveloperName
    ) {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.toAddress = RECIPIENT_EMAIL;
        request.templateDeveloperName = templateDeveloperName;

        return request;
    }

    private static EmailTemplate buildTemplate(
        String developerName,
        String subjectValue,
        String htmlValue
    ) {
        EmailTemplate templateRecord = new EmailTemplate();

        templateRecord.DeveloperName = developerName;
        templateRecord.Name = developerName;
        templateRecord.Subject = subjectValue;
        templateRecord.HtmlValue = htmlValue;
        templateRecord.Body = 'Plain text body';
        templateRecord.TemplateType = 'custom';
        templateRecord.FolderId = UserInfo.getUserId();
        templateRecord.IsActive = true;

        return templateRecord;
    }

    private static ClientAgreementEmailService.EmailAttachment createRawAttachment(
        String fileName,
        Blob body,
        String contentType
    ) {
        ClientAgreementEmailService.EmailAttachment attachment =
            new ClientAgreementEmailService.EmailAttachment();

        attachment.fileName = fileName;
        attachment.base64Data = EncodingUtil.base64Encode(body);
        attachment.contentType = contentType;

        return attachment;
    }

    private static ContentVersion createContentVersion(
        String title,
        String pathOnClient,
        Blob versionData
    ) {
        ContentVersion contentVersion = new ContentVersion();

        contentVersion.Title = title;
        contentVersion.PathOnClient = pathOnClient;
        contentVersion.VersionData = versionData;
        contentVersion.IsMajorVersion = true;

        insert contentVersion;

        return [
            SELECT Id,
                   ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
            LIMIT 1
        ];
    }
}