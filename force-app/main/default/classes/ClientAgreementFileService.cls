/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementFileService
 * Author          : <YourName>
 * Created Date    : Jun 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 10, 2026
 * Description     : Service class for saving agreement PDFs as Salesforce Files.
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public inherited sharing class ClientAgreementFileService {

    public static Id savePdfFile(
        String fileName,
        String base64Pdf,
        Id linkedEntityId
    ) {
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('File name is required.');
        }

        if (String.isBlank(base64Pdf)) {
            throw new AuraHandledException('PDF content is missing.');
        }

        String cleanedBase64 = base64Pdf;

        if (cleanedBase64.contains(',')) {
            cleanedBase64 = cleanedBase64.substringAfter(',');
        }

        Blob pdfBlob;

        try {
            pdfBlob = EncodingUtil.base64Decode(cleanedBase64);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid PDF Base64 content: ' + e.getMessage());
        }

        return savePdfFileFromBlob(fileName, pdfBlob, linkedEntityId);
    }

    public static Id savePdfFileFromBlob(
        String fileName,
        Blob pdfBlob,
        Id linkedEntityId
    ) {
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('File name is required.');
        }

        if (pdfBlob == null) {
            throw new AuraHandledException('PDF Blob content is missing.');
        }

        if (linkedEntityId == null) {
            throw new AuraHandledException('Linked record Id is required.');
        }

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName.replace('.pdf', '');
        cv.PathOnClient = fileName;
        cv.VersionData = pdfBlob;

        /*
         * Important:
         * Use FirstPublishLocationId instead of manually creating ContentDocumentLink.
         * Manual ContentDocumentLink insert can fail for guest/public users with:
         * "You don't have permission to share this file."
         */
        cv.FirstPublishLocationId = linkedEntityId;

        try {
            insert cv;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Failed to create PDF file. ' + e.getDmlMessage(0)
            );
        }

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        return insertedVersion.Id;
    }
}