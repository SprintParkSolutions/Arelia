/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementEmailServiceTest
 * Author          : Arelia
 * Created Date    : Jun 29, 2026
 * Last Modified By: Arelia
 * Last Modified On: Jun 29, 2026
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * @description Unit tests for ClientAgreementEmailService.
 * Covers email templates, fallback email content, merge values,
 * external supporting links, entity and raw attachments,
 * MIME normalization, filename sanitization, Base64 validation,
 * invalid requests, and Org-Wide Email Address lookup.
 */
 
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.TooManyMethods')
private class ClientAgreementEmailServiceTest {
    private static final String RECIPIENT_EMAIL = 'client@example.com';
    private static final String SUPERVISOR_EMAIL = 'supervisor@example.com';
    private static final String TEMPLATE_ONE = 'Client_Agreement_Template_One';
    private static final String TEMPLATE_TWO = 'Client_Agreement_Template_Two';
    private static final String TEMPLATE_THREE = 'Client_Agreement_Template_Three';
    private static final String TEMPLATE_FOUR = 'Client_Agreement_Template_Four';
    private static final String TEMPLATE_FIVE = 'Client_Agreement_Template_Five';
    private static final String MISSING_TEMPLATE = 'Template_That_Does_Not_Exist';
    private static final String SIGNING_URL = 'https://example.com/sign';
    private static final String EXTERNAL_FILE_URL = 'https://drive.google.com/file/d/test123/view';
    private static final String EXTERNAL_FILE_HTML = '<a href="' + EXTERNAL_FILE_URL + '">View Supporting File</a>';

    @TestSetup
    static void setupData() {
        insert new List<EmailTemplate>{
            buildTemplate(
                TEMPLATE_ONE,
                'Agreement for {{CLIENT_EMAIL}}',
                '<html><body>Hello {{CLIENT_EMAIL}} - ' +
                '{{OPPORTUNITY_NAME}}</body></html>'
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

    /**
     * @description Tests email template processing,
     * merge values, and a raw PDF attachment.
     */
    @IsTest
    static void sendEmailShouldSendUsingTemplateAndRawPdfAttachment() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_ONE);

        request.attachmentFileName = 'Client Agreement';

        request.attachmentBase64 = EncodingUtil.base64Encode(
            Blob.valueOf('PDF body')
        );

        request.attachmentContentType = 'application/pdf';

        request.mergeValues = new Map<String, String>{
            'CLIENT_EMAIL' => RECIPIENT_EMAIL,
            'OPPORTUNITY_NAME' => 'Test Opportunity'
        };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests entity attachments and
     * multiple additional raw attachments.
     */
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

        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.attachmentContentVersionId = mainVersion.Id;

        request.entityAttachmentContentVersionIds =
            new List<Id>{
                supportingVersion.Id
            };

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'design-image',
                    Blob.valueOf('PNG body'),
                    'image/png'
                ),
                createRawAttachment(
                    'site-photo.jpeg',
                    Blob.valueOf('JPEG body'),
                    'image/jpg'
                ),
                skippedAttachment,
                null
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests MIME type detection
     * using file extensions.
     */
    @IsTest
    static void sendEmailShouldNormalizeContentTypeFromFileName() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_THREE);

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'supporting-document.pdf',
                    Blob.valueOf('PDF body'),
                    null
                ),
                createRawAttachment(
                    'site-photo.jpg',
                    Blob.valueOf('JPG body'),
                    null
                ),
                createRawAttachment(
                    'design-image.png',
                    Blob.valueOf('PNG body'),
                    null
                ),
                createRawAttachment(
                    'unknown-file',
                    Blob.valueOf('Unknown body'),
                    null
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests Base64 data URI handling
     * and unsafe attachment filename sanitization.
     */
    @IsTest
    static void sendEmailShouldHandleDataUriBase64AndUnsafeFileName() {
        String dataUri =
            'data:application/pdf;base64,' +
            EncodingUtil.base64Encode(
                Blob.valueOf('PDF data uri body')
            );

        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_FOUR);

        request.attachmentFileName =
            'Client/Agreement:Final?Version';

        request.attachmentBase64 = dataUri;
        request.attachmentContentType = 'application/pdf';

        assertEmailCompletes(request);
    }

    /**
     * @description Verifies that the new fallback
     * email body is used when template name is null.
     */
    @IsTest
    static void sendEmailShouldUseFallbackWhenTemplateNameIsBlank() {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.toAddress = RECIPIENT_EMAIL;
        request.templateDeveloperName = null;

        request.mergeValues = createFallbackMergeValues();

        assertEmailCompletes(request);
    }

    /**
     * @description Verifies fallback email processing
     * when the specified template does not exist.
     */
    @IsTest
    static void sendEmailShouldUseFallbackWhenTemplateDoesNotExist() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(MISSING_TEMPLATE);

        request.mergeValues = createFallbackMergeValues();

        assertEmailCompletes(request);
    }

    /**
     * @description Tests fallback email without attachments
     * or merge values.
     */
    @IsTest
    static void sendEmailShouldSendWithOnlyFallbackBodyAndNoAttachments() {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.toAddress = RECIPIENT_EMAIL;
        request.templateDeveloperName = '';

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>();

        assertEmailCompletes(request);
    }

    /**
     * @description Tests merge replacement when
     * one of the values is null.
     */
    @IsTest
    static void sendEmailShouldReplaceNullMergeValueWithBlank() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_ONE);

        request.mergeValues = new Map<String, String>{
            'CLIENT_EMAIL' => null,
            'OPPORTUNITY_NAME' => 'Null Merge Opportunity'
        };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests default attachment filename
     * and JPEG filename normalization.
     */
    @IsTest
    static void sendEmailShouldHandleBlankFileNameAndJpegContentType() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    null,
                    Blob.valueOf('Default filename body'),
                    'application/pdf'
                ),
                createRawAttachment(
                    'photo-without-extension',
                    Blob.valueOf('JPEG body'),
                    'image/jpeg'
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests that blank main attachment
     * content is ignored safely.
     */
    @IsTest
    static void sendEmailShouldSkipBlankBase64RawMainAttachment() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.attachmentFileName = 'Blank.pdf';
        request.attachmentBase64 = '';
        request.attachmentContentType = 'application/pdf';

        assertEmailCompletes(request);
    }

    /**
     * @description Tests the new external supporting
     * file links merge field in the fallback email.
     */
    @IsTest
    static void sendEmailShouldHandleExternalFileLinksInFallback() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(null);

        request.mergeValues = createFallbackMergeValues();

        assertEmailCompletes(request);
    }

    /**
     * @description Tests fallback email when
     * external file links are empty.
     */
    @IsTest
    static void sendEmailShouldHandleBlankExternalFileLinks() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(null);

        request.mergeValues = createFallbackMergeValues();

        request.mergeValues.put(
            'EXTERNAL_FILE_LINKS',
            ''
        );

        assertEmailCompletes(request);
    }

    /**
     * @description Tests fallback email when
     * external file links merge value is null.
     */
    @IsTest
    static void sendEmailShouldHandleNullExternalFileLinks() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(MISSING_TEMPLATE);

        request.mergeValues = createFallbackMergeValues();

        request.mergeValues.put(
            'EXTERNAL_FILE_LINKS',
            null
        );

        assertEmailCompletes(request);
    }

    /**
     * @description Tests the complete set of merge
     * fields used by the Client Agreement controller.
     */
    @IsTest
    static void sendEmailShouldHandleAllAgreementMergeFields() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(null);

        request.mergeValues = createFallbackMergeValues();

        request.attachmentFileName = 'Agreement.pdf';

        request.attachmentBase64 =
            EncodingUtil.base64Encode(
                Blob.valueOf('Client agreement PDF')
            );

        request.attachmentContentType = 'application/pdf';

        assertEmailCompletes(request);
    }

    /**
     * @description Tests file attachment processing
     * with case-insensitive MIME types.
     */
    @IsTest
    static void sendEmailShouldNormalizeUppercaseContentTypes() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'Document',
                    Blob.valueOf('PDF content'),
                    'APPLICATION/PDF'
                ),
                createRawAttachment(
                    'Image',
                    Blob.valueOf('PNG content'),
                    'IMAGE/PNG'
                ),
                createRawAttachment(
                    'Photo',
                    Blob.valueOf('JPEG content'),
                    'IMAGE/JPEG'
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests MIME detection with uppercase
     * file extensions and missing MIME types.
     */
    @IsTest
    static void sendEmailShouldHandleUppercaseFileExtensions() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'Agreement.PDF',
                    Blob.valueOf('PDF content'),
                    null
                ),
                createRawAttachment(
                    'Design.PNG',
                    Blob.valueOf('PNG content'),
                    null
                ),
                createRawAttachment(
                    'Photo.JPEG',
                    Blob.valueOf('JPEG content'),
                    null
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests sanitization of invalid
     * characters in attachment filenames.
     */
    @IsTest
    static void sendEmailShouldSanitizeUnsafeAttachmentFileNames() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'Client\\Agreement/File:Final*Version?.pdf',
                    Blob.valueOf('PDF content'),
                    'application/pdf'
                ),
                createRawAttachment(
                    'Design"Image<Test>|Final',
                    Blob.valueOf('PNG content'),
                    'image/png'
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests the handling of filenames
     * that already have supported extensions.
     */
    @IsTest
    static void sendEmailShouldPreserveExistingFileExtensions() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'Agreement.pdf',
                    Blob.valueOf('PDF body'),
                    'application/pdf'
                ),
                createRawAttachment(
                    'Image.png',
                    Blob.valueOf('PNG body'),
                    'image/png'
                ),
                createRawAttachment(
                    'Photo.jpeg',
                    Blob.valueOf('JPEG body'),
                    'image/jpeg'
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests attachment content type fallback
     * for unsupported MIME values.
     */
    @IsTest
    static void sendEmailShouldHandleUnsupportedContentType() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'unknown-file',
                    Blob.valueOf('Unknown content'),
                    'application/custom'
                ),
                createRawAttachment(
                    'document.pdf',
                    Blob.valueOf('PDF content'),
                    'application/custom'
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests skipping null and empty
     * additional attachments.
     */
    @IsTest
    static void sendEmailShouldSkipNullAndEmptyAdditionalAttachments() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        ClientAgreementEmailService.EmailAttachment emptyAttachment =
            new ClientAgreementEmailService.EmailAttachment();

        emptyAttachment.fileName = 'Empty.pdf';
        emptyAttachment.base64Data = '';
        emptyAttachment.contentType = 'application/pdf';

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                null,
                emptyAttachment,
                createRawAttachment(
                    'Valid.pdf',
                    Blob.valueOf('Valid PDF body'),
                    'application/pdf'
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests sending raw PDF and image
     * attachments together.
     */
    @IsTest
    static void sendEmailShouldHandleMixedRawAttachments() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.attachmentFileName = 'MainAgreement.pdf';

        request.attachmentBase64 =
            EncodingUtil.base64Encode(
                Blob.valueOf('Main Agreement')
            );

        request.attachmentContentType = 'application/pdf';

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                createRawAttachment(
                    'Design.png',
                    Blob.valueOf('PNG body'),
                    'image/png'
                ),
                createRawAttachment(
                    'SitePhoto.jpg',
                    Blob.valueOf('JPG body'),
                    'image/jpeg'
                )
            };

        assertEmailCompletes(request);
    }

    /**
     * @description Tests email processing when
     * entity attachment IDs are an empty list.
     */
    @IsTest
    static void sendEmailShouldHandleEmptyEntityAttachmentList() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        request.entityAttachmentContentVersionIds =
            new List<Id>();

        assertEmailCompletes(request);
    }

    /**
     * @description Tests request validation
     * when request is null.
     */
    @IsTest
    static void sendEmailShouldThrowWhenRequestIsNull() {
        assertSendThrows(
            null,
            'Missing request should throw exception.'
        );
    }

    /**
     * @description Tests request validation
     * when recipient email is missing.
     */
    @IsTest
    static void sendEmailShouldThrowWhenRecipientIsBlank() {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.templateDeveloperName = TEMPLATE_ONE;

        assertSendThrows(
            request,
            'Missing recipient should throw exception.'
        );
    }

    /**
     * @description Tests invalid Base64 data
     * in the main raw attachment.
     */
    @IsTest
    static void sendEmailShouldThrowWhenBase64IsInvalid() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_FIVE);

        request.attachmentFileName = 'Invalid.pdf';
        request.attachmentBase64 = 'invalid-base64-value';
        request.attachmentContentType = 'application/pdf';

        assertSendThrows(
            request,
            'Invalid Base64 should throw exception.'
        );
    }

    /**
     * @description Tests invalid Base64 data
     * in an additional attachment.
     */
    @IsTest
    static void sendEmailShouldThrowForInvalidAdditionalAttachment() {
        ClientAgreementEmailService.EmailRequest request =
            createBaseRequest(TEMPLATE_TWO);

        ClientAgreementEmailService.EmailAttachment invalidAttachment =
            new ClientAgreementEmailService.EmailAttachment();

        invalidAttachment.fileName = 'InvalidImage.png';
        invalidAttachment.base64Data = 'invalid-base64-value';
        invalidAttachment.contentType = 'image/png';

        request.additionalAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>{
                invalidAttachment
            };

        assertSendThrows(
            request,
            'Invalid additional attachment Base64 should throw exception.'
        );
    }

    /**
     * @description Tests Org-Wide Email Address lookup
     * using the configured custom label.
     */
    @IsTest
    static void getOrgWideEmailAddressIdFromLabelShouldCompleteSafely() {
        Boolean completed = false;

        Test.startTest();

        ClientAgreementEmailService.getOrgWideEmailAddressIdFromLabel();

        completed = true;

        Test.stopTest();

        System.assertEquals(
            true,
            completed,
            'OWD lookup should complete safely.'
        );
    }

    /**
     * @description Verifies that the email service
     * completes without exceptions and invokes email sending.
     */
    private static void assertEmailCompletes(
        ClientAgreementEmailService.EmailRequest request
    ) {
        Boolean completed = false;

        Test.startTest();

        Integer emailInvocationsBefore = Limits.getEmailInvocations();

        ClientAgreementEmailService.sendEmail(request);

        Integer emailInvocationsAfter = Limits.getEmailInvocations();

        completed = true;

        System.assertEquals(
            emailInvocationsBefore + 1,
            emailInvocationsAfter,
            'Email service should invoke Messaging.sendEmail once.'
        );

        Test.stopTest();

        System.assertEquals(
            true,
            completed,
            'Email service should complete without exception.'
        );
    }

    /**
     * @description Verifies that invalid requests
     * throw an AuraHandledException.
     */
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

            System.assertNotEquals(
                null,
                exceptionRecord,
                'Exception should be available.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            assertionMessage
        );
    }

    /**
     * @description Creates a base email request.
     */
    private static ClientAgreementEmailService.EmailRequest createBaseRequest(
        String templateDeveloperName
    ) {
        ClientAgreementEmailService.EmailRequest request =
            new ClientAgreementEmailService.EmailRequest();

        request.toAddress = RECIPIENT_EMAIL;
        request.templateDeveloperName = templateDeveloperName;

        return request;
    }

    /**
     * @description Creates all merge values required
     * by the updated Client Agreement fallback email.
     */
    private static Map<String, String> createFallbackMergeValues() {
        return new Map<String, String>{
            'LEAD_NAME' => 'Test Client',
            'OPPORTUNITY_NAME' => 'Test Opportunity',
            'CLIENT_EMAIL' => RECIPIENT_EMAIL,
            'SUPERVISOR_EMAIL' => SUPERVISOR_EMAIL,
            'SIGNING_URL' => SIGNING_URL,
            'EXTERNAL_FILE_LINKS' => EXTERNAL_FILE_HTML
        };
    }

    /**
     * @description Builds a custom email template
     * for test scenarios.
     */
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

    /**
     * @description Creates an additional raw email attachment.
     */
    private static ClientAgreementEmailService.EmailAttachment createRawAttachment(
        String fileName,
        Blob body,
        String contentType
    ) {
        ClientAgreementEmailService.EmailAttachment attachment =
            new ClientAgreementEmailService.EmailAttachment();

        attachment.fileName = fileName;

        attachment.base64Data =
            EncodingUtil.base64Encode(body);

        attachment.contentType = contentType;

        return attachment;
    }

    /**
     * @description Creates a ContentVersion record
     * for entity attachment testing.
     */
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