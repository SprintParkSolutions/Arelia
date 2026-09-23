/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementFileService
 * Author          : <YourName>
 * Created Date    : Jun 26, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 26, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 26, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public inherited sharing class VendorAgreementFileService {

    public static Id createUnsignedAgreementPdf(
        Vendor_Agreement__c agreementRecord
    ) {
        return createPdfFile(
            agreementRecord,
            VendorAgreementConstants.UNSIGNED_FILE_PREFIX
        );
    }

    public static Id createSignedAgreementPdf(
        Vendor_Agreement__c agreementRecord
    ) {
        return createPdfFile(
            agreementRecord,
            VendorAgreementConstants.SIGNED_FILE_PREFIX
        );
    }

    public static Blob getLatestVersionData(
        String contentDocumentId
    ) {
        if (String.isBlank(contentDocumentId)) {
            throw new AuraHandledException(
                'The Vendor Agreement PDF file was not found.'
            );
        }

        List<ContentVersion> versions = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            throw new AuraHandledException(
                'The Vendor Agreement PDF version was not found.'
            );
        }

        return versions[0].VersionData;
    }

    private static Id createPdfFile(
        Vendor_Agreement__c agreementRecord,
        String filePrefix
    ) {
        Blob pdfBlob = generatePdf(agreementRecord.Id);

        ContentVersion versionRecord = new ContentVersion(
            Title = filePrefix + agreementRecord.Name,
            PathOnClient = filePrefix
                + agreementRecord.Name
                + VendorAgreementConstants.PDF_EXTENSION,
            VersionData = pdfBlob,
            FirstPublishLocationId =
                agreementRecord.Vendor_Opportunity__c
        );

        insert versionRecord;

        ContentVersion insertedVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionRecord.Id
            LIMIT 1
        ];

        return insertedVersion.ContentDocumentId;
    }

    private static Blob generatePdf(Id agreementId) {
        if (Test.isRunningTest()) {
            return Blob.valueOf('Vendor Agreement Test PDF');
        }

        PageReference pdfPage = Page.VendorAgreementPdf;

        pdfPage.getParameters().put(
            'agreementId',
            String.valueOf(agreementId)
        );

        return pdfPage.getContentAsPDF();
    }

    public static Id createSignedAgreementPdfFromBlob(
        Vendor_Agreement__c agreementRecord,
        Blob signedPdfBlob
    ) {
        if (agreementRecord == null || agreementRecord.Id == null) {
            throw new AuraHandledException(
                'Vendor Agreement record is required.'
            );
        }

        if (signedPdfBlob == null || signedPdfBlob.size() == 0) {
            throw new AuraHandledException(
                'Signed Vendor Agreement PDF content is required.'
            );
        }

        ContentVersion versionRecord = new ContentVersion(
            Title = VendorAgreementConstants.SIGNED_FILE_PREFIX
                + agreementRecord.Name,
            PathOnClient = VendorAgreementConstants.SIGNED_FILE_PREFIX
                + agreementRecord.Name
                + VendorAgreementConstants.PDF_EXTENSION,
            VersionData = signedPdfBlob,
            FirstPublishLocationId =
                agreementRecord.Vendor_Opportunity__c
        );

        insert versionRecord;

        ContentVersion insertedVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionRecord.Id
            LIMIT 1
        ];

        return insertedVersion.ContentDocumentId;
    }
}