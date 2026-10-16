/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementAttachmentServiceTest
 * Author          : Arelia
 * Created Date    : Jun 29, 2026
 * Last Modified By: Arelia
 * Last Modified On: Sep 9, 2026
 * Description     : Test class for ClientAgreementAttachmentService.
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 29, 2026  │ Arelia       │ Initial version
 *  Sep 9, 2026   │ Arelia       │ Updated Agreement Preview image tests to verify
 *                │              │ only images referenced in Agreement_HTML__c are
 *                │              │ returned. Removed supporting files remain on the
 *                │              │ Opportunity but are excluded from agreement preview.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * @description Test class for ClientAgreementAttachmentService.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.TooManyMethods,PMD.ExcessiveClassLength')
private class ClientAgreementAttachmentServiceTest {

    private static final String PDF_CONTENT_TYPE = 'application/pdf';
    private static final String PNG_CONTENT_TYPE = 'image/png';
    private static final String JPEG_CONTENT_TYPE = 'image/jpeg';


    @IsTest
    static void getSupportingFilesShouldReturnSalesforceFilesAndAttachments() {

        Account parentRecord = createAccount('Supporting Parent');

        ContentVersion pdfVersion =
            createContentVersion(
                'Floor Plan',
                'floor-plan.pdf',
                Blob.valueOf('PDF content'),
                parentRecord.Id
            );

        createContentVersion(
            'Design Image',
            'design.png',
            Blob.valueOf('PNG content'),
            parentRecord.Id
        );

        createClassicAttachment(
            parentRecord.Id,
            'classic-support.pdf',
            PDF_CONTENT_TYPE,
            Blob.valueOf('Classic PDF content')
        );

        Test.startTest();

        List<ClientAgreementDTO.SupportingFileDTO> files = ClientAgreementAttachmentService.getSupportingFiles(parentRecord.Id);
        Test.stopTest();

        System.assertEquals(3, files.size(), 'Three supported files should be returned.');
        System.assertEquals(true, containsFileName(files, 'Floor Plan.pdf'));
        System.assertEquals(true, containsFileName(files, 'Design Image.png'));
        System.assertEquals(true, containsFileName(files, 'classic-support.pdf'));
        ClientAgreementDTO.SupportingFileDTO pdfFile = getFileByName(files, 'Floor Plan.pdf');
        System.assertEquals(true, pdfFile.isPdf, 'PDF flag should be true.');
        System.assertEquals(PDF_CONTENT_TYPE, pdfFile.contentType);
        System.assertNotEquals(null, pdfFile.base64Data);
        System.assertEquals(getContentDocumentId(pdfVersion.Id), pdfFile.contentDocumentId);
        ClientAgreementDTO.SupportingFileDTO imageFile = getFileByName(files, 'Design Image.png');
        System.assertEquals(true, imageFile.isImage, 'Image flag should be true.');
        System.assertEquals(PNG_CONTENT_TYPE, imageFile.contentType);
        System.assertNotEquals(null, imageFile.base64Data);
    }


    @IsTest
    static void getSupportingFilesShouldReturnEmptyForNullId() {

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> files = ClientAgreementAttachmentService.getSupportingFiles(null);
        Test.stopTest();

        System.assertEquals(
            0,
            files.size(),
            'Null record Id should return no files.'
        );
    }


    @IsTest
    static void getSupportingFilesShouldSkipUnsupportedAndGeneratedAgreementFiles() {

        Account parentRecord = createAccount('Skip Parent');

        createContentVersion(
            'Client_Agreement_CA001',
            'Client_Agreement_CA001.pdf',
            Blob.valueOf('Generated agreement'),
            parentRecord.Id
        );

        createContentVersion(
            'Notes Text File',
            'notes.txt',
            Blob.valueOf('Text file'),
            parentRecord.Id
        );

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> files = ClientAgreementAttachmentService.getSupportingFiles(parentRecord.Id);
        Test.stopTest();
        System.assertEquals(0, files.size(), 'Generated agreement and unsupported files should be skipped.');
    }


    @IsTest
    static void getSupportingFilesShouldUseFileNameWhenAttachmentContentTypeBlank() {

        Account parentRecord = createAccount('Classic Blank Content Type Parent');
        createClassicAttachment(parentRecord.Id, 'fallback-image.jpg', null, Blob.valueOf('Image body'));
        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> files = ClientAgreementAttachmentService.getSupportingFiles(parentRecord.Id);
        Test.stopTest();
        System.assertEquals(1, files.size(), 'Attachment should be detected from file extension.');
        System.assertEquals('fallback-image.jpg', files[0].fileName);
        System.assertEquals(JPEG_CONTENT_TYPE, files[0].contentType);
        System.assertEquals(true, files[0].isImage);
    }


    @IsTest
    static void getSupportingFilesShouldSkipUnsupportedClassicAttachments() {

        Account parentRecord = createAccount('Unsupported Classic Parent');

        createClassicAttachment(
            parentRecord.Id,
            'unsupported.txt',
            'text/plain',
            Blob.valueOf('Text body')
        );

        createClassicAttachment(
            parentRecord.Id,
            'noextension',
            null,
            Blob.valueOf('No extension body')
        );

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> files = ClientAgreementAttachmentService.getSupportingFiles(parentRecord.Id);
        Test.stopTest();
        System.assertEquals(0, files.size(), 'Unsupported classic attachments should be skipped.');
    }


    @IsTest
    static void getSupportingPdfEmailAttachmentsShouldReturnOnlyPdfFiles() {

        Account parentRecord = createAccount('PDF Email Parent');

        createContentVersion(
            'Selected PDF',
            'selected.pdf',
            Blob.valueOf('PDF content'),
            parentRecord.Id
        );

        createContentVersion(
            'Selected Image',
            'selected.jpg',
            Blob.valueOf('JPG content'),
            parentRecord.Id
        );

        Test.startTest();
        List<ClientAgreementEmailService.EmailAttachment> attachments = ClientAgreementAttachmentService.getSupportingPdfEmailAttachments(parentRecord.Id);
        Test.stopTest();
        System.assertEquals(1, attachments.size(), 'Only PDF attachment should be returned.');
        System.assertEquals('Selected PDF.pdf', attachments[0].fileName);
        System.assertEquals(PDF_CONTENT_TYPE, attachments[0].contentType);
        System.assertNotEquals(null, attachments[0].base64Data);
    }


    @IsTest
    static void getSeparateSupportingEmailAttachmentsShouldExcludeReferencedImage() {

        Account parentRecord = createAccount('Separate Attachment Parent');

        ContentVersion imageVersion =
            createContentVersion(
                'Referenced Image',
                'referenced.png',
                Blob.valueOf('Referenced image'),
                parentRecord.Id
            );

        createContentVersion(
            'Separate PDF',
            'separate.pdf',
            Blob.valueOf('Separate PDF'),
            parentRecord.Id
        );

        String contentDocumentId = String.valueOf(getContentDocumentId(imageVersion.Id));

        String agreementHtml =
            '<p>Image reference: ' +
            contentDocumentId +
            '</p>';

        Test.startTest();
        List<ClientAgreementEmailService.EmailAttachment> attachments = ClientAgreementAttachmentService.getSeparateSupportingEmailAttachments(parentRecord.Id, agreementHtml);
        Test.stopTest();
        System.assertEquals(1, attachments.size(), 'Referenced image should be excluded.');
        System.assertEquals('Separate PDF.pdf', attachments[0].fileName);
        System.assertEquals(PDF_CONTENT_TYPE, attachments[0].contentType);
    }


    @IsTest
    static void getSeparateSupportingEmailAttachmentsShouldIncludeUnreferencedImageAndPdf() {

        Account parentRecord = createAccount('Unreferenced Separate Parent');

        createContentVersion(
            'Unreferenced Image',
            'unreferenced.png',
            Blob.valueOf('Image body'),
            parentRecord.Id
        );

        createContentVersion(
            'Unreferenced PDF',
            'unreferenced.pdf',
            Blob.valueOf('PDF body'),
            parentRecord.Id
        );

        Test.startTest();
        List<ClientAgreementEmailService.EmailAttachment> attachments = ClientAgreementAttachmentService.getSeparateSupportingEmailAttachments(parentRecord.Id,'<p>No Salesforce file id here.</p>');
        Test.stopTest();
        System.assertEquals(2, attachments.size(), 'Unreferenced image and PDF should be returned.');
        System.assertEquals(true, containsEmailAttachment(attachments, 'Unreferenced Image.png'));
        System.assertEquals(true, containsEmailAttachment(attachments, 'Unreferenced PDF.pdf'));
    }


    @IsTest
    static void linkOpportunitySupportingFilesToAgreementShouldLinkSupportedFiles() {

        Account sourceRecord = createAccount('Source Record');
        Account targetRecord = createAccount('Target Record');

        ContentVersion pdfVersion =
            createContentVersion(
                'Linkable PDF',
                'linkable.pdf',
                Blob.valueOf('PDF content'),
                sourceRecord.Id
            );

        createContentVersion(
            'Unsupported Text',
            'unsupported.txt',
            Blob.valueOf('Text content'),
            sourceRecord.Id
        );

        Test.startTest();
        ClientAgreementAttachmentService.linkOpportunitySupportingFilesToAgreement(sourceRecord.Id, targetRecord.Id);

        /*
         * Call again to verify duplicate link protection.
         */
        ClientAgreementAttachmentService.linkOpportunitySupportingFilesToAgreement(sourceRecord.Id, targetRecord.Id);
        Test.stopTest();
        Id pdfDocumentId = getContentDocumentId(pdfVersion.Id);
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :targetRecord.Id AND ContentDocumentId = :pdfDocumentId];
        System.assertEquals(1, links.size(), 'Supported file should be linked only once.');
    }


    @IsTest
    static void linkOpportunitySupportingFilesToAgreementShouldReturnWhenNoSupportedFiles() {

        Account sourceRecord = createAccount('No Supported Source');
        Account targetRecord = createAccount('No Supported Target');

        createContentVersion(
            'Unsupported File',
            'unsupported.txt',
            Blob.valueOf('Unsupported content'),
            sourceRecord.Id
        );

        Test.startTest();
        ClientAgreementAttachmentService.linkOpportunitySupportingFilesToAgreement(sourceRecord.Id, targetRecord.Id);
        Test.stopTest();
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :targetRecord.Id];
        System.assertEquals(0, links.size(), 'No files should be linked.');
    }


    @IsTest
    static void linkSpecificSupportingFilesToAgreementShouldLinkOnlyValidSupportedFiles() {

        Account parentRecord = createAccount('Specific Source');
        Account targetRecord = createAccount('Specific Target');

        ContentVersion pdfVersion =
            createContentVersion(
                'Specific PDF',
                'specific.pdf',
                Blob.valueOf('PDF content'),
                parentRecord.Id
            );

        ContentVersion generatedAgreementVersion =
            createContentVersion(
                'Client_Agreement_Old',
                'Client_Agreement_Old.pdf',
                Blob.valueOf(
                    'Generated agreement content'
                ),
                parentRecord.Id
            );

        Id pdfDocumentId = getContentDocumentId(pdfVersion.Id);
        Id generatedAgreementDocumentId = getContentDocumentId(generatedAgreementVersion.Id);

        List<String> documentIds =
            new List<String>{
                String.valueOf(
                    pdfDocumentId
                ),
                String.valueOf(
                    generatedAgreementDocumentId
                ),
                'invalid-id'
            };

        Test.startTest();
        ClientAgreementAttachmentService.linkSpecificSupportingFilesToAgreement(targetRecord.Id, documentIds);

        /*
         * Verify duplicate protection.
         */
        ClientAgreementAttachmentService.linkSpecificSupportingFilesToAgreement(targetRecord.Id, documentIds);
        Test.stopTest();
        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :targetRecord.Id];
        System.assertEquals(1, links.size(), 'Only one supported non-agreement file should be linked.');
        System.assertEquals(pdfDocumentId, links[0].ContentDocumentId);
    }


    @IsTest
    static void linkSpecificSupportingFilesToAgreementShouldReturnForOnlyInvalidIds() {

        Account targetRecord = createAccount('Invalid Specific Target');
        Test.startTest();

        ClientAgreementAttachmentService.linkSpecificSupportingFilesToAgreement(
                targetRecord.Id,
                new List<String>{
                    'invalid-id',
                    null,
                    ''
                }
            );

        Test.stopTest();
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :targetRecord.Id];
        System.assertEquals(0, links.size(), 'Invalid ids should not create links.');
    }


    @IsTest
    static void getEmailAttachmentsByContentDocumentIdsShouldReturnSupportedAttachments() {

        Account parentRecord = createAccount('Email Attachment Parent');

        ContentVersion pdfVersion =
            createContentVersion(
                'Email PDF',
                'email.pdf',
                Blob.valueOf('Email PDF content'),
                parentRecord.Id
            );

        ContentVersion imageVersion =
            createContentVersion(
                'Email Image',
                'email.jpeg',
                Blob.valueOf(
                    'Email Image content'
                ),
                parentRecord.Id
            );

        List<String> documentIds =
            new List<String>{
                String.valueOf(
                    getContentDocumentId(
                        pdfVersion.Id
                    )
                ),
                String.valueOf(
                    getContentDocumentId(
                        imageVersion.Id
                    )
                ),
                'invalid-id'
            };

        Test.startTest();
        List<ClientAgreementEmailService.EmailAttachment> attachments = ClientAgreementAttachmentService.getEmailAttachmentsByContentDocumentIds(documentIds);
        Test.stopTest();
        System.assertEquals(2, attachments.size(), 'PDF and image should be returned.');
        System.assertEquals(true, containsEmailAttachment(attachments, 'Email PDF.pdf'));
        System.assertEquals(true, containsEmailAttachment(attachments, 'Email Image.jpeg'));
    }


    @IsTest
    static void getEmailAttachmentsByContentDocumentIdsShouldSkipGeneratedAndUnsupportedFiles() {

        Account parentRecord = createAccount('Email Skip Parent');

        ContentVersion generatedAgreementVersion =
            createContentVersion(
                'Client_Agreement_Generated',
                'Client_Agreement_Generated.pdf',
                Blob.valueOf('Generated PDF'),
                parentRecord.Id
            );

        ContentVersion unsupportedVersion =
            createContentVersion(
                'Unsupported File',
                'unsupported.txt',
                Blob.valueOf(
                    'Unsupported content'
                ),
                parentRecord.Id
            );

        Test.startTest();
        List<ClientAgreementEmailService.EmailAttachment> attachments = ClientAgreementAttachmentService.getEmailAttachmentsByContentDocumentIds(
                    new List<String>{
                        String.valueOf(getContentDocumentId(generatedAgreementVersion.Id)),
                        String.valueOf(getContentDocumentId(unsupportedVersion.Id))
                    }
                );

        Test.stopTest();
        System.assertEquals(0, attachments.size(), 'Generated agreement and unsupported files should be skipped.');
    }


    @IsTest
    static void getLatestContentVersionIdsByContentDocumentIdsShouldReturnLatestVersions() {

        Account parentRecord = createAccount('Latest Version Parent');

        ContentVersion pdfVersion =
            createContentVersion(
                'Latest PDF',
                'latest.pdf',
                Blob.valueOf(
                    'Latest PDF content'
                ),
                parentRecord.Id
            );

        Id documentId = getContentDocumentId(pdfVersion.Id);

        Test.startTest();
        List<Id> versionIds = ClientAgreementAttachmentService.getLatestContentVersionIdsByContentDocumentIds(new List<String>{String.valueOf(documentId), 'bad-id'});
        Test.stopTest();
        System.assertEquals(1, versionIds.size(), 'One latest version should be returned.');
        System.assertEquals(pdfVersion.Id, versionIds[0]);
    }


    @IsTest
    static void getLatestContentVersionIdsShouldSkipGeneratedAgreementAndUnsupportedFiles() {

        Account parentRecord = createAccount('Latest Skip Parent');

        ContentVersion generatedAgreementVersion =
            createContentVersion(
                'Client_Agreement_Generated',
                'Client_Agreement_Generated.pdf',
                Blob.valueOf(
                    'Generated PDF'
                ),
                parentRecord.Id
            );

        ContentVersion unsupportedVersion =
            createContentVersion(
                'Unsupported Latest',
                'unsupported.txt',
                Blob.valueOf(
                    'Unsupported content'
                ),
                parentRecord.Id
            );

        Test.startTest();

        List<Id> versionIds = ClientAgreementAttachmentService.getLatestContentVersionIdsByContentDocumentIds(new List<String>{String.valueOf(getContentDocumentId(generatedAgreementVersion.Id)),
                        String.valueOf(getContentDocumentId(unsupportedVersion.Id))
                    }
                );

        Test.stopTest();
        System.assertEquals(0, versionIds.size(), 'No latest versions should be returned.');
    }


    @IsTest
    static void getAllSupportedEmailAttachmentsShouldReturnImagesAndPdfs() {

        Account parentRecord = createAccount('All Supported Parent');

        createContentVersion(
            'All PDF',
            'all.pdf',
            Blob.valueOf(
                'All PDF content'
            ),
            parentRecord.Id
        );

        createContentVersion(
            'All Image',
            'all.png',
            Blob.valueOf(
                'All Image content'
            ),
            parentRecord.Id
        );

        Test.startTest();
        List<ClientAgreementEmailService.EmailAttachment> attachments = ClientAgreementAttachmentService.getAllSupportedEmailAttachments(parentRecord.Id);
        Test.stopTest();
        System.assertEquals(2, attachments.size(), 'All supported files should be returned.');
    }


    @IsTest
    static void getAllSupportedEmailAttachmentsShouldReturnEmptyForNullId() {

        Test.startTest();
        List<ClientAgreementEmailService.EmailAttachment> attachments = ClientAgreementAttachmentService.getAllSupportedEmailAttachments(null);
        Test.stopTest();
        System.assertEquals(0, attachments.size(), 'Null id should return empty attachments.');
    }


    /*
     * ============================================================
     * UPDATED TEST:
     *
     * Only an image referenced in Agreement_HTML__c should be
     * returned for the Agreement Preview.
     *
     * An unreferenced image may still remain on the Opportunity,
     * but it must not appear inside the Agreement Preview.
     * ============================================================
     */
    @IsTest
    static void getAgreementImageFilesShouldReturnOnlyReferencedImage() {

        Account opportunityRecord = createAccount('Opportunity Like Record');
        Account agreementRecord = createAccount('Agreement Like Record');

        ContentVersion referencedImageVersion =
            createContentVersion(
                'Referenced Agreement Image',
                'referenced-agreement.png',
                Blob.valueOf(
                    'Referenced image'
                ),
                opportunityRecord.Id
            );

        ContentVersion unreferencedImageVersion =
            createContentVersion(
                'Removed Supporting Image',
                'removed-supporting.jpg',
                Blob.valueOf(
                    'Removed supporting image'
                ),
                opportunityRecord.Id
            );

        /*
         * Simulate an existing Salesforce file that remains
         * available on the Opportunity.
         *
         * The presence of the file itself must not cause it
         * to appear in the Agreement Preview.
         */
        Id unreferencedDocumentId = getContentDocumentId(unreferencedImageVersion.Id);

        /*
         * Reference only the first image in Agreement_HTML__c.
         *
         * The service supports references using either
         * ContentDocumentId or ContentVersionId.
         */
        String referencedDocumentId = String.valueOf(getContentDocumentId(referencedImageVersion.Id));

        String agreementHtml =
            '<p>Agreement Body</p>' +
            '<img src="/sfc/servlet.shepherd/document/download/' +
            referencedDocumentId +
            '" />';

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> imageFiles = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(opportunityRecord.Id, agreementRecord.Id, agreementHtml);
        Test.stopTest();
        System.assertEquals(1, imageFiles.size(), 'Only the image referenced in Agreement HTML should be returned.');
        System.assertEquals('Referenced Agreement Image.png', imageFiles[0].fileName, 'Referenced agreement image should be returned.');
        System.assertEquals(referencedDocumentId, imageFiles[0].contentDocumentId, 'Returned image should match the referenced ContentDocumentId.');
        System.assertEquals(false, containsFileName(imageFiles, 'Removed Supporting Image.jpg'), 'Unreferenced/removed supporting image must not appear in Agreement Preview.');

        /*
         * Verify the removed/unreferenced file still exists
         * in Salesforce and remains linked to the Opportunity.
         *
         * This confirms the feature filters the Agreement Preview
         * without deleting or unlinking the Salesforce file.
         */
        List<ContentDocumentLink> remainingLinks = [SELECT Id, ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId = :opportunityRecord.Id AND ContentDocumentId = :unreferencedDocumentId];
        System.assertEquals(1, remainingLinks.size(), 'Removed supporting image should remain linked to the Opportunity.');
    }


    /*
     * ============================================================
     * NEW COVERAGE:
     *
     * Verify ContentVersionId references are also recognized.
     * isFileReferencedInAgreementHtml() supports both
     * ContentDocumentId and ContentVersionId.
     * ============================================================
     */
    @IsTest
    static void getAgreementImageFilesShouldRecognizeContentVersionIdReference() {

        Account opportunityRecord = createAccount('Version Reference Parent');
        Account agreementRecord = createAccount('Version Reference Agreement');

        ContentVersion imageVersion =
            createContentVersion(
                'Version Referenced Image',
                'version-reference.png',
                Blob.valueOf(
                    'Version referenced image'
                ),
                opportunityRecord.Id
            );

        String agreementHtml =
            '<p>Agreement Image</p>' +
            '<img src="/sfc/servlet.shepherd/version/download/' +
            String.valueOf(
                imageVersion.Id
            ) +
            '" />';

        Test.startTest();

        List<ClientAgreementDTO.SupportingFileDTO> imageFiles = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(opportunityRecord.Id, agreementRecord.Id, agreementHtml);
        Test.stopTest();
        System.assertEquals(1, imageFiles.size(), 'Image referenced by ContentVersionId should be returned.');
        System.assertEquals('Version Referenced Image.png', imageFiles[0].fileName);
        System.assertEquals(String.valueOf(imageVersion.Id), imageFiles[0].contentVersionId);
    }


    /*
     * ============================================================
     * UPDATED TEST:
     *
     * agreementId can be null because Agreement Preview image
     * selection is now based on Agreement_HTML__c references.
     * ============================================================
     */
    @IsTest
    static void getAgreementImageFilesShouldReturnReferencedImageWhenAgreementIdNull() {

        Account opportunityRecord = createAccount('Agreement Null Image Parent');

        ContentVersion imageVersion =
            createContentVersion(
                'Agreement Image',
                'agreement-image.png',
                Blob.valueOf(
                    'Image body'
                ),
                opportunityRecord.Id
            );

        String documentId = String.valueOf(getContentDocumentId(imageVersion.Id));

        String agreementHtml =
            '<p>Agreement Body</p>' +
            '<img data-content-document-id="' +
            documentId +
            '" />';

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> imageFiles = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(opportunityRecord.Id, null, agreementHtml);
        Test.stopTest();
        System.assertEquals(1, imageFiles.size(), 'Referenced image should still be returned when agreement Id is null.');
        System.assertEquals('Agreement Image.png', imageFiles[0].fileName);
    }


    /*
     * ============================================================
     * NEW COVERAGE:
     *
     * An image that exists on the Opportunity but is not referenced
     * inside Agreement_HTML__c must not appear in Agreement Preview.
     *
     * This specifically covers the Remove Supporting File feature.
     * ============================================================
     */
    @IsTest
    static void getAgreementImageFilesShouldExcludeUnreferencedOpportunityImage() {

        Account opportunityRecord = createAccount('Removed Image Parent');
        Account agreementRecord = createAccount('Removed Image Agreement');

        ContentVersion removedImageVersion =
            createContentVersion(
                'Removed Image',
                'removed-image.jpg',
                Blob.valueOf(
                    'Removed image body'
                ),
                opportunityRecord.Id
            );

        Id documentId = getContentDocumentId(removedImageVersion.Id);
        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> imageFiles = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(opportunityRecord.Id, agreementRecord.Id, '<p>Agreement body without supporting image reference.</p>');
        Test.stopTest();
        System.assertEquals(0, imageFiles.size(), 'Unreferenced Opportunity image must not appear in Agreement Preview.');

        /*
         * Confirm the physical Salesforce file was not removed.
         */
        List<ContentDocumentLink> opportunityLinks = [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :opportunityRecord.Id AND ContentDocumentId = :documentId];

        System.assertEquals(1, opportunityLinks.size(), 'Excluded image must remain stored and linked to the Opportunity.');
    }


    /*
     * ============================================================
     * NEW COVERAGE:
     *
     * Blank Agreement HTML must not cause Opportunity images
     * to automatically appear in Agreement Preview.
     * ============================================================
     */
    @IsTest
    static void getAgreementImageFilesShouldReturnEmptyWhenAgreementHtmlBlank() {

        Account opportunityRecord = createAccount('Blank Agreement HTML Parent');
        Account agreementRecord = createAccount('Blank Agreement HTML Agreement');

        createContentVersion(
            'Existing Opportunity Image',
            'existing-image.png',
            Blob.valueOf(
                'Existing image'
            ),
            opportunityRecord.Id
        );

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> imageFiles = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(opportunityRecord.Id, agreementRecord.Id, null);
        Test.stopTest();
        System.assertEquals(0, imageFiles.size(), 'Blank Agreement HTML should return no Agreement Preview images.');
    }


    /*
     * ============================================================
     * NEW COVERAGE:
     *
     * PDFs may be present on Opportunity but should never be
     * returned as Agreement Preview images.
     * ============================================================
     */
    @IsTest
    static void getAgreementImageFilesShouldIgnorePdfEvenWhenReferenced() {

        Account opportunityRecord = createAccount('Referenced PDF Parent');
        Account agreementRecord = createAccount('Referenced PDF Agreement');

        ContentVersion pdfVersion =
            createContentVersion(
                'Referenced PDF',
                'referenced.pdf',
                Blob.valueOf(
                    'Referenced PDF body'
                ),
                opportunityRecord.Id
            );

        String documentId = String.valueOf(getContentDocumentId(pdfVersion.Id));

        String agreementHtml =
            '<p>PDF reference: ' +
            documentId +
            '</p>';

        Test.startTest();

        List<ClientAgreementDTO.SupportingFileDTO> imageFiles = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(opportunityRecord.Id, agreementRecord.Id, agreementHtml);
        Test.stopTest();
        System.assertEquals(0, imageFiles.size(), 'PDF files must not be returned as Agreement Preview images.');
    }


    @IsTest
    static void getAgreementImageFilesShouldReturnEmptyForNullOpportunityId() {

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> imageFiles = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(null, null, '<p>Agreement body</p>');
        Test.stopTest();
        System.assertEquals(0, imageFiles.size(), 'Null Opportunity Id should return no Agreement Preview images.');
    }


    @IsTest
    static void publicMethodsShouldHandleNullAndEmptyInputs() {

        Test.startTest();
        ClientAgreementAttachmentService.linkOpportunitySupportingFilesToAgreement(null, null);
        ClientAgreementAttachmentService.linkSpecificSupportingFilesToAgreement(null, null);
        List<ClientAgreementEmailService.EmailAttachment> emailAttachments = ClientAgreementAttachmentService.getEmailAttachmentsByContentDocumentIds(null);
        List<Id> versionIds = ClientAgreementAttachmentService.getLatestContentVersionIdsByContentDocumentIds(new List<String>());
        List<ClientAgreementDTO.SupportingFileDTO> agreementImages = ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(null, null, null);
        
        Test.stopTest();

        System.assertEquals(0, emailAttachments.size(), 'Null input should return no email attachments.');
        System.assertEquals(0, versionIds.size(), 'Empty input should return no version ids.');
        System.assertEquals(0, agreementImages.size(), 'Null Agreement Preview inputs should return no images.');
    }


    /*
     * ============================================================
     * TEST HELPERS
     * ============================================================
     */

    private static Account createAccount(String accountName) {

        Account accountRecord = new Account();
        accountRecord.Name = accountName;
        insert accountRecord;
        return accountRecord;
    }


    private static ContentVersion createContentVersion(String title, String pathOnClient, Blob versionData, Id firstPublishLocationId) {

        ContentVersion contentVersion = new ContentVersion();
        contentVersion.Title = title;
        contentVersion.PathOnClient = pathOnClient;
        contentVersion.VersionData = versionData;
        contentVersion.FirstPublishLocationId = firstPublishLocationId;
        contentVersion.IsMajorVersion = true;
        insert contentVersion;

        return [
            SELECT Id,
                   ContentDocumentId,
                   Title,
                   FileExtension,
                   FileType
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
            LIMIT 1
        ];
    }


    private static Attachment createClassicAttachment(Id parentId, String fileName, String contentType, Blob body) {

        Attachment attachmentRecord = new Attachment();
        attachmentRecord.ParentId = parentId;
        attachmentRecord.Name = fileName;
        attachmentRecord.ContentType = contentType;
        attachmentRecord.Body = body;
        insert attachmentRecord;
        return attachmentRecord;
    }


    private static Id getContentDocumentId(Id contentVersionId) {

        ContentVersion versionRecord = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1];
        return versionRecord.ContentDocumentId;
    }


    private static Boolean containsFileName(List<ClientAgreementDTO.SupportingFileDTO> files, String fileName) {

        return getFileByName(
            files,
            fileName
        ) != null;
    }


    private static ClientAgreementDTO.SupportingFileDTO getFileByName(List<ClientAgreementDTO.SupportingFileDTO> files, String fileName) {

        for (
            ClientAgreementDTO.SupportingFileDTO fileDto :
            files
        ) {

            if (
                fileDto != null &&
                fileDto.fileName == fileName
            ) {
                return fileDto;
            }
        }

        return null;
    }


    private static Boolean containsEmailAttachment(List<ClientAgreementEmailService.EmailAttachment> attachments, String fileName) {

        for (
            ClientAgreementEmailService.EmailAttachment attachment :
            attachments
        ) {

            if (
                attachment != null &&
                attachment.fileName == fileName
            ) {
                return true;
            }
        }

        return false;
    }
}