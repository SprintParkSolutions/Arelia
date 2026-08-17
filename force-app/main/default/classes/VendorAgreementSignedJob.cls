/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementSignedJob
 * Author          : <YourName>
 * Created Date    : Jul 7, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 7, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 7, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class VendorAgreementSignedJob
    implements Queueable {

    private final Id agreementId;
    private final Id signatureRequestId;

    public VendorAgreementSignedJob(
        Id agreementId,
        Id signatureRequestId
    ) {
        this.agreementId = agreementId;
        this.signatureRequestId = signatureRequestId;
    }

    public void execute(QueueableContext queueableContext) {
        try {
            Vendor_Agreement_Signature__c signatureRequest = [
                SELECT Id,
                       Submission_Status__c
                FROM Vendor_Agreement_Signature__c
                WHERE Id = :signatureRequestId
                LIMIT 1
            ];

            Vendor_Agreement__c agreementRecord = [
                SELECT Id,
                       Name,
                       Agreement_Status__c,
                       Vendor_Opportunity__c,
                       Signed_File_Id__c
                FROM Vendor_Agreement__c
                WHERE Id = :agreementId
                LIMIT 1
            ];

            if (
                agreementRecord.Agreement_Status__c
                != VendorAgreementConstants.STATUS_SIGNED
            ) {
                throw new AuraHandledException(
                    'Vendor Agreement is not in Signed status.'
                );
            }

            String signedPdfBase64 =
                rebuildSignedPdfBase64(signatureRequestId);

            if (String.isBlank(signedPdfBase64)) {
                throw new AuraHandledException(
                    'Signed Vendor Agreement PDF content is missing.'
                );
            }

            Blob signedPdfBlob =
                decodePdfBase64(signedPdfBase64);

            if (
                signedPdfBlob == null
                || signedPdfBlob.size() == 0
            ) {
                throw new AuraHandledException(
                    'Signed Vendor Agreement PDF is invalid.'
                );
            }

            Id signedFileId =
                VendorAgreementFileService.createSignedAgreementPdfFromBlob(agreementRecord, signedPdfBlob);

            update new Vendor_Agreement__c(
                Id = agreementRecord.Id,
                Signed_File_Id__c = String.valueOf(signedFileId)
            );

            if (agreementRecord.Vendor_Opportunity__c != null) {
                update new Vendor_Opportunity__c(
                    Id = agreementRecord.Vendor_Opportunity__c,
                    Vendor_Agreement_Signed__c = true
                );
            }

            agreementRecord.Signed_File_Id__c =
                String.valueOf(signedFileId);

            VendorAgreementEmailService.sendSignedAgreementToSupervisor(agreementRecord);

            update new Vendor_Agreement_Signature__c(
                Id = signatureRequest.Id,
                Submission_Status__c = 'Processed',
                Processed_Date__c = System.now(),
                Processing_Error__c = null
            );
        } catch (Exception exceptionValue) {
            markFailed(
                exceptionValue.getMessage()
            );
        }
    }

    private static String rebuildSignedPdfBase64(
        Id signatureRequestId
    ) {
        if (signatureRequestId == null) {
            return null;
        }

        List<Vendor_Agreement_Signature_Chunk__c> chunks = [
            SELECT Sequence__c,
                   Chunk_Data__c
            FROM Vendor_Agreement_Signature_Chunk__c
            WHERE Signature_Request_Id__c =
                :String.valueOf(signatureRequestId)
            ORDER BY Sequence__c ASC
        ];

        String combinedPdfBase64 = '';

        for (
            Vendor_Agreement_Signature_Chunk__c chunkRecord
            : chunks
        ) {
            if (!String.isBlank(chunkRecord.Chunk_Data__c)) {
                combinedPdfBase64 += chunkRecord.Chunk_Data__c;
            }
        }

        return combinedPdfBase64;
    }

    private static Blob decodePdfBase64(
        String signedPdfBase64
    ) {
        if (String.isBlank(signedPdfBase64)) {
            return null;
        }

        String cleanedBase64 = signedPdfBase64;

        if (cleanedBase64.contains(',')) {
            cleanedBase64 =
                cleanedBase64.substringAfter(',');
        }

        return EncodingUtil.base64Decode(cleanedBase64);
    }

    private void markFailed(String errorMessage) {
        if (signatureRequestId == null) {
            return;
        }

        update new Vendor_Agreement_Signature__c(
            Id = signatureRequestId,
            Submission_Status__c = 'Failed',
            Processing_Error__c = leftSafe(
                errorMessage,
                32768
            ),
            Processed_Date__c = System.now()
        );
    }

    private static String leftSafe(
        String value,
        Integer maximumLength
    ) {
        if (String.isBlank(value)) {
            return null;
        }

        return value.length() > maximumLength
            ? value.left(maximumLength)
            : value;
    }
}