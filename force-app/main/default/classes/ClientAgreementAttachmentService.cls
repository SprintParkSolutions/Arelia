/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementAttachmentService
 * Author          : <YourName>
 * Created Date    : Jun 12, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 12, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 12, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class ClientAgreementAttachmentService {

    private static final Integer MAX_FILES = 18;
    private static final Integer MAX_SINGLE_FILE_BYTES = 3000000;
    private static final Integer MAX_PDF_ATTACHMENT_BYTES = 10000000;

    public static List<ClientAgreementDTO.SupportingFileDTO> getSupportingFiles(Id linkedRecordId) {
        List<ClientAgreementDTO.SupportingFileDTO> files =
            new List<ClientAgreementDTO.SupportingFileDTO>();

        if (linkedRecordId == null) {
            return files;
        }

        loadSalesforceFiles(linkedRecordId, files);
        loadClassicAttachments(linkedRecordId, files);

        return files;
    }

    /*
     * Existing PDF-only method kept for backward compatibility.
     */
    public static List<ClientAgreementEmailService.EmailAttachment> getSupportingPdfEmailAttachments(
        Id linkedRecordId
    ) {
        List<ClientAgreementEmailService.EmailAttachment> emailAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>();

        for (ClientAgreementDTO.SupportingFileDTO fileDto : getSupportingFiles(linkedRecordId)) {
            if (fileDto == null || fileDto.isPdf != true) {
                continue;
            }

            if (String.isBlank(fileDto.base64Data)) {
                continue;
            }

            emailAttachments.add(buildEmailAttachment(fileDto));
        }

        return emailAttachments;
    }

    /*
     * New method:
     * Returns file-upload-section images/PDFs as separate attachments.
     *
     * Rich-text images are excluded because their ContentDocumentId/ContentVersionId
     * is referenced inside Agreement_HTML__c and they remain part of the agreement PDF.
     */
    public static List<ClientAgreementEmailService.EmailAttachment> getSeparateSupportingEmailAttachments(
        Id linkedRecordId,
        String agreementHtml
    ) {
        List<ClientAgreementEmailService.EmailAttachment> emailAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>();

        for (ClientAgreementDTO.SupportingFileDTO fileDto : getSupportingFiles(linkedRecordId)) {
            if (fileDto == null) {
                continue;
            }

            if (String.isBlank(fileDto.base64Data)) {
                continue;
            }

            if (fileDto.isImage != true && fileDto.isPdf != true) {
                continue;
            }

            /*
             * If the image is referenced in agreement HTML, it is a rich-text image.
             * It should stay inside the agreement PDF and should not be sent separately.
             */
            if (fileDto.isImage == true && isFileReferencedInAgreementHtml(fileDto, agreementHtml)) {
                continue;
            }

            emailAttachments.add(buildEmailAttachment(fileDto));
        }

        return emailAttachments;
    }

    private static ClientAgreementEmailService.EmailAttachment buildEmailAttachment(
        ClientAgreementDTO.SupportingFileDTO fileDto
    ) {
        ClientAgreementEmailService.EmailAttachment emailAttachment =
            new ClientAgreementEmailService.EmailAttachment();

        emailAttachment.fileName = fileDto.fileName;
        emailAttachment.contentType = fileDto.contentType;
        emailAttachment.base64Data = fileDto.base64Data;

        return emailAttachment;
    }

    private static Boolean isFileReferencedInAgreementHtml(
        ClientAgreementDTO.SupportingFileDTO fileDto,
        String agreementHtml
    ) {
        if (fileDto == null || String.isBlank(agreementHtml)) {
            return false;
        }

        String html = agreementHtml;

        if (!String.isBlank(fileDto.contentDocumentId)
            && containsSalesforceId(html, fileDto.contentDocumentId)) {
            return true;
        }

        if (!String.isBlank(fileDto.contentVersionId)
            && containsSalesforceId(html, fileDto.contentVersionId)) {
            return true;
        }

        return false;
    }

    private static Boolean containsSalesforceId(String text, String recordId) {
        if (String.isBlank(text) || String.isBlank(recordId)) {
            return false;
        }

        if (text.contains(recordId)) {
            return true;
        }

        if (recordId.length() >= 15 && text.contains(recordId.left(15))) {
            return true;
        }

        return false;
    }

    private static void loadSalesforceFiles(
        Id linkedRecordId,
        List<ClientAgreementDTO.SupportingFileDTO> files
    ) {
        if (files.size() >= MAX_FILES) {
            return;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :linkedRecordId
            LIMIT 50
        ];

        Set<Id> versionIds = new Set<Id>();
        Map<Id, Id> versionIdToDocumentId = new Map<Id, Id>();

        for (ContentDocumentLink linkRecord : links) {
            if (linkRecord.ContentDocument == null) {
                continue;
            }

            String title = linkRecord.ContentDocument.Title;
            String fileType = linkRecord.ContentDocument.FileType;

            /*
             * Avoid attaching previously generated agreement PDFs again.
             */
            if (!String.isBlank(title) && title.startsWith('Client_Agreement_')) {
                continue;
            }

            if (!isSupportedFileType(fileType)) {
                continue;
            }

            if (linkRecord.ContentDocument.LatestPublishedVersionId != null) {
                Id versionId = linkRecord.ContentDocument.LatestPublishedVersionId;
                versionIds.add(versionId);
                versionIdToDocumentId.put(versionId, linkRecord.ContentDocumentId);
            }
        }

        if (versionIds.isEmpty()) {
            return;
        }

        List<ContentVersion> versions = [
            SELECT Id,
                   Title,
                   FileExtension,
                   FileType,
                   VersionData,
                   ContentSize,
                   ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds
            LIMIT 50
        ];

        for (ContentVersion cv : versions) {
            if (files.size() >= MAX_FILES) {
                break;
            }

            String contentType = getContentType(cv.FileExtension, cv.FileType);

            if (String.isBlank(contentType)) {
                continue;
            }

            Boolean isPdfFile = contentType == 'application/pdf';
            Boolean isImageFile = isImageContentType(contentType);

            /*
            * For images, keep existing behavior:
            * image must have base64Data because it may be rendered inside agreement PDF.
            *
            * For PDFs, allow metadata even if file is large.
            * PDF is not embedded into generated agreement PDF.
            * PDF is sent later as separate attachment by ContentDocumentId.
            */
            Boolean shouldLoadBase64 = true;

            if (cv.ContentSize != null && cv.ContentSize > MAX_SINGLE_FILE_BYTES) {
                if (isImageFile) {
                    continue;
                }

                if (isPdfFile) {
                    shouldLoadBase64 = false;
                }
            }

            ClientAgreementDTO.SupportingFileDTO fileDto =
                new ClientAgreementDTO.SupportingFileDTO();

            fileDto.title = cv.Title;
            fileDto.fileName = buildFileName(cv.Title, cv.FileExtension);
            fileDto.contentType = contentType;
            fileDto.isImage = isImageFile;
            fileDto.isPdf = isPdfFile;
            fileDto.source = 'Salesforce File';
            fileDto.contentVersionId = String.valueOf(cv.Id);

            if (cv.ContentDocumentId != null) {
                fileDto.contentDocumentId = String.valueOf(cv.ContentDocumentId);
            } else if (versionIdToDocumentId.containsKey(cv.Id)) {
                fileDto.contentDocumentId = String.valueOf(versionIdToDocumentId.get(cv.Id));
            }

            if (shouldLoadBase64) {
                fileDto.base64Data = EncodingUtil.base64Encode(cv.VersionData);
            } else {
                fileDto.base64Data = null;
            }

            files.add(fileDto);
        }
    }

    private static void loadClassicAttachments(
        Id linkedRecordId,
        List<ClientAgreementDTO.SupportingFileDTO> files
    ) {
        if (files.size() >= MAX_FILES) {
            return;
        }

        List<Attachment> attachments = [
            SELECT Id,
                   Name,
                   Body,
                   BodyLength,
                   ContentType
            FROM Attachment
            WHERE ParentId = :linkedRecordId
            LIMIT 50
        ];

        for (Attachment att : attachments) {
            if (files.size() >= MAX_FILES) {
                break;
            }

            if (att.BodyLength != null && att.BodyLength > MAX_SINGLE_FILE_BYTES) {
                continue;
            }

            if (!isSupportedContentType(att.ContentType, att.Name)) {
                continue;
            }

            String contentType = att.ContentType;

            if (String.isBlank(contentType)) {
                contentType = getContentTypeFromFileName(att.Name);
            }

            if (String.isBlank(contentType)) {
                continue;
            }

            ClientAgreementDTO.SupportingFileDTO fileDto =
                new ClientAgreementDTO.SupportingFileDTO();

            fileDto.title = att.Name;
            fileDto.fileName = att.Name;
            fileDto.contentType = contentType;
            fileDto.base64Data = EncodingUtil.base64Encode(att.Body);
            fileDto.isImage = isImageContentType(contentType);
            fileDto.isPdf = contentType == 'application/pdf';
            fileDto.source = 'Classic Attachment';

            /*
             * Classic attachments are not rich-text image files.
             * They will be treated as separate supporting attachments.
             */
            fileDto.contentDocumentId = null;
            fileDto.contentVersionId = null;

            files.add(fileDto);
        }
    }

    private static Boolean isSupportedFileType(String fileType) {
        if (String.isBlank(fileType)) {
            return false;
        }

        String ft = fileType.toUpperCase();

        return ft == 'PNG'
            || ft == 'JPG'
            || ft == 'JPEG'
            || ft == 'PDF';
    }

    private static Boolean isSupportedContentType(String contentType, String fileName) {
        if (!String.isBlank(contentType)) {
            String ct = contentType.toLowerCase();

            if (ct == 'image/png'
                || ct == 'image/jpeg'
                || ct == 'image/jpg'
                || ct == 'application/pdf') {
                return true;
            }
        }

        String fileContentType = getContentTypeFromFileName(fileName);

        return !String.isBlank(fileContentType);
    }

    private static String getContentType(String fileExtension, String fileType) {
        String ext = '';

        if (!String.isBlank(fileExtension)) {
            ext = fileExtension.toLowerCase();
        } else if (!String.isBlank(fileType)) {
            ext = fileType.toLowerCase();
        }

        if (ext == 'png') {
            return 'image/png';
        }

        if (ext == 'jpg' || ext == 'jpeg') {
            return 'image/jpeg';
        }

        if (ext == 'pdf') {
            return 'application/pdf';
        }

        return null;
    }

    private static String getContentTypeFromFileName(String fileName) {
        if (String.isBlank(fileName) || !fileName.contains('.')) {
            return null;
        }

        String ext = fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase();

        return getContentType(ext, ext);
    }

    private static Boolean isImageContentType(String contentType) {
        if (String.isBlank(contentType)) {
            return false;
        }

        String ct = contentType.toLowerCase();

        return ct == 'image/png'
            || ct == 'image/jpeg'
            || ct == 'image/jpg';
    }

    private static String buildFileName(String title, String extension) {
        if (String.isBlank(title)) {
            title = 'Supporting_File';
        }

        if (String.isBlank(extension)) {
            return title;
        }

        if (title.toLowerCase().endsWith('.' + extension.toLowerCase())) {
            return title;
        }

        return title + '.' + extension;
    }

    public static void linkOpportunitySupportingFilesToAgreement(
        Id opportunityId,
        Id agreementId
    ) {
        if (opportunityId == null || agreementId == null) {
            return;
        }

        List<ContentDocumentLink> opportunityLinks = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :opportunityId
            LIMIT 50
        ];

        if (opportunityLinks.isEmpty()) {
            return;
        }

        Set<Id> supportedDocumentIds = new Set<Id>();

        for (ContentDocumentLink linkRecord : opportunityLinks) {
            if (linkRecord.ContentDocument == null) {
                continue;
            }

            String title = linkRecord.ContentDocument.Title;
            String fileType = linkRecord.ContentDocument.FileType;

            if (!String.isBlank(title) && title.startsWith('Client_Agreement_')) {
                continue;
            }

            if (!isSupportedFileType(fileType)) {
                continue;
            }

            supportedDocumentIds.add(linkRecord.ContentDocumentId);
        }

        if (supportedDocumentIds.isEmpty()) {
            return;
        }

        Set<Id> alreadyLinkedDocumentIds = new Set<Id>();

        for (ContentDocumentLink existingLink : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :agreementId
            AND ContentDocumentId IN :supportedDocumentIds
        ]) {
            alreadyLinkedDocumentIds.add(existingLink.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();

        for (Id contentDocumentId : supportedDocumentIds) {
            if (alreadyLinkedDocumentIds.contains(contentDocumentId)) {
                continue;
            }

            ContentDocumentLink newLink = new ContentDocumentLink();
            newLink.ContentDocumentId = contentDocumentId;
            newLink.LinkedEntityId = agreementId;
            newLink.ShareType = 'V';
            newLink.Visibility = 'AllUsers';

            linksToInsert.add(newLink);
        }

        if (!linksToInsert.isEmpty()) {
            insert linksToInsert;
        }
    }

    public static void linkSpecificSupportingFilesToAgreement(
        Id agreementId,
        List<String> contentDocumentIdValues
    ) {
        if (agreementId == null
            || contentDocumentIdValues == null
            || contentDocumentIdValues.isEmpty()) {
            return;
        }

        Set<Id> contentDocumentIds = toIdSet(contentDocumentIdValues);

        if (contentDocumentIds.isEmpty()) {
            return;
        }

        Set<Id> supportedDocumentIds = new Set<Id>();

        for (ContentDocument documentRecord : [
            SELECT Id, Title, FileType
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ]) {
            if (!String.isBlank(documentRecord.Title)
                && documentRecord.Title.startsWith('Client_Agreement_')) {
                continue;
            }

            if (!isSupportedFileType(documentRecord.FileType)) {
                continue;
            }

            supportedDocumentIds.add(documentRecord.Id);
        }

        if (supportedDocumentIds.isEmpty()) {
            return;
        }

        Set<Id> alreadyLinkedDocumentIds = new Set<Id>();

        for (ContentDocumentLink existingLink : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :agreementId
            AND ContentDocumentId IN :supportedDocumentIds
        ]) {
            alreadyLinkedDocumentIds.add(existingLink.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();

        for (Id contentDocumentId : supportedDocumentIds) {
            if (alreadyLinkedDocumentIds.contains(contentDocumentId)) {
                continue;
            }

            ContentDocumentLink linkRecord = new ContentDocumentLink();
            linkRecord.ContentDocumentId = contentDocumentId;
            linkRecord.LinkedEntityId = agreementId;
            linkRecord.ShareType = 'V';
            linkRecord.Visibility = 'AllUsers';

            linksToInsert.add(linkRecord);
        }

        if (!linksToInsert.isEmpty()) {
            insert linksToInsert;
        }
    }

    public static List<ClientAgreementEmailService.EmailAttachment> getEmailAttachmentsByContentDocumentIds(
        List<String> contentDocumentIdValues
    ) {
        List<ClientAgreementEmailService.EmailAttachment> emailAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>();

        if (contentDocumentIdValues == null || contentDocumentIdValues.isEmpty()) {
            return emailAttachments;
        }

        Set<Id> contentDocumentIds = toIdSet(contentDocumentIdValues);

        if (contentDocumentIds.isEmpty()) {
            return emailAttachments;
        }

        List<ContentDocument> documents = [
            SELECT Id,
                Title,
                FileType,
                LatestPublishedVersionId
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
            LIMIT 50
        ];

        Set<Id> versionIds = new Set<Id>();

        for (ContentDocument documentRecord : documents) {
            if (!String.isBlank(documentRecord.Title)
                && documentRecord.Title.startsWith('Client_Agreement_')) {
                continue;
            }

            if (!isSupportedFileType(documentRecord.FileType)) {
                continue;
            }

            if (documentRecord.LatestPublishedVersionId != null) {
                versionIds.add(documentRecord.LatestPublishedVersionId);
            }
        }

        if (versionIds.isEmpty()) {
            return emailAttachments;
        }

        for (ContentVersion cv : [
            SELECT Id,
                Title,
                FileExtension,
                FileType,
                VersionData,
                ContentSize
            FROM ContentVersion
            WHERE Id IN :versionIds
            LIMIT 50
        ]) {
            String contentType = getContentType(cv.FileExtension, cv.FileType);

            if (String.isBlank(contentType)) {
                continue;
            }

            Boolean isPdfFile = contentType == 'application/pdf';
            Boolean isImageFile = isImageContentType(contentType);

            /*
            * Keep existing image protection.
            * Allow PDFs up to higher PDF attachment limit.
            */
            if (cv.ContentSize != null) {
                if (isImageFile && cv.ContentSize > MAX_SINGLE_FILE_BYTES) {
                    continue;
                }

                if (isPdfFile && cv.ContentSize > MAX_PDF_ATTACHMENT_BYTES) {
                    continue;
                }

                if (!isImageFile && !isPdfFile && cv.ContentSize > MAX_SINGLE_FILE_BYTES) {
                    continue;
                }
            }

            ClientAgreementEmailService.EmailAttachment emailAttachment =
                new ClientAgreementEmailService.EmailAttachment();

            emailAttachment.fileName = buildFileName(cv.Title, cv.FileExtension);
            emailAttachment.contentType = contentType;
            emailAttachment.base64Data = EncodingUtil.base64Encode(cv.VersionData);

            emailAttachments.add(emailAttachment);
        }

        return emailAttachments;
    }

    public static List<Id> getLatestContentVersionIdsByContentDocumentIds(
        List<String> contentDocumentIdValues
    ) {
        List<Id> contentVersionIds = new List<Id>();

        if (contentDocumentIdValues == null || contentDocumentIdValues.isEmpty()) {
            return contentVersionIds;
        }

        Set<Id> contentDocumentIds = toIdSet(contentDocumentIdValues);

        if (contentDocumentIds.isEmpty()) {
            return contentVersionIds;
        }

        for (ContentDocument documentRecord : [
            SELECT Id,
                Title,
                FileType,
                LatestPublishedVersionId
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
            LIMIT 50
        ]) {
            if (!String.isBlank(documentRecord.Title)
                && documentRecord.Title.startsWith('Client_Agreement_')) {
                continue;
            }

            if (!isSupportedFileType(documentRecord.FileType)) {
                continue;
            }

            if (documentRecord.LatestPublishedVersionId != null) {
                contentVersionIds.add(documentRecord.LatestPublishedVersionId);
            }
        }

        return contentVersionIds;
    }

    public static List<ClientAgreementEmailService.EmailAttachment> getAllSupportedEmailAttachments(
        Id linkedRecordId
    ) {
        List<ClientAgreementEmailService.EmailAttachment> emailAttachments =
            new List<ClientAgreementEmailService.EmailAttachment>();

        for (ClientAgreementDTO.SupportingFileDTO fileDto : getSupportingFiles(linkedRecordId)) {
            if (fileDto == null || String.isBlank(fileDto.base64Data)) {
                continue;
            }

            if (fileDto.isImage != true && fileDto.isPdf != true) {
                continue;
            }

            ClientAgreementEmailService.EmailAttachment emailAttachment =
                new ClientAgreementEmailService.EmailAttachment();

            emailAttachment.fileName = fileDto.fileName;
            emailAttachment.contentType = fileDto.contentType;
            emailAttachment.base64Data = fileDto.base64Data;

            emailAttachments.add(emailAttachment);
        }

        return emailAttachments;
    }

    public static List<ClientAgreementDTO.SupportingFileDTO> getAgreementImageFilesExcludingAgreementAttachments(
        Id opportunityId,
        Id agreementId
    ) {
        List<ClientAgreementDTO.SupportingFileDTO> allOpportunityFiles =
            getSupportingFiles(opportunityId);

        Set<String> separateAttachmentDocumentIds = new Set<String>();

        if (agreementId != null) {
            for (ContentDocumentLink linkRecord : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :agreementId
            ]) {
                separateAttachmentDocumentIds.add(String.valueOf(linkRecord.ContentDocumentId));
            }
        }

        List<ClientAgreementDTO.SupportingFileDTO> agreementImages =
            new List<ClientAgreementDTO.SupportingFileDTO>();

        for (ClientAgreementDTO.SupportingFileDTO fileDto : allOpportunityFiles) {
            if (fileDto == null || fileDto.isImage != true) {
                continue;
            }

            if (!String.isBlank(fileDto.contentDocumentId)
                && separateAttachmentDocumentIds.contains(fileDto.contentDocumentId)) {
                continue;
            }

            agreementImages.add(fileDto);
        }

        return agreementImages;
    }

    private static Set<Id> toIdSet(List<String> idValues) {
        Set<Id> ids = new Set<Id>();

        if (idValues == null) {
            return ids;
        }

        for (String idValue : idValues) {
            if (String.isBlank(idValue)) {
                continue;
            }

            try {
                ids.add((Id) idValue);
            } catch (Exception e) {
                // Ignore invalid Id values.
            }
        }

        return ids;
    }
}