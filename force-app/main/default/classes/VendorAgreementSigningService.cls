/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementSigningService
 * Author          : <YourName>
 * Created Date    : Jul 6, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 6, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 6, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class VendorAgreementSigningService {

    private static final Integer PDF_CHUNK_SIZE = 120000;

    public class SigningResponse {
        @AuraEnabled public String agreementName;
        @AuraEnabled public String agreementHtml;
        @AuraEnabled public String vendorName;
    }

    @AuraEnabled
    public static SigningResponse getAgreementById(
        Id agreementId
    ) {
        Vendor_Agreement__c agreementRecord =
            getAgreementByIdInternal(agreementId);

        if (
            agreementRecord.Agreement_Status__c
            == VendorAgreementConstants.STATUS_SIGNED
        ) {
            throw new AuraHandledException(
                'This Vendor Agreement has already been signed.'
            );
        }

        List<Vendor_Agreement_Signature__c> signatureRequests = [
            SELECT Id,
                   Submission_Status__c
            FROM Vendor_Agreement_Signature__c
            WHERE Vendor_Agreement__c = :agreementId
            AND Submission_Status__c IN (
                'Submitted',
                'Processing',
                'Processed'
            )
            LIMIT 1
        ];

        if (!signatureRequests.isEmpty()) {
            throw new AuraHandledException(
                'A signature has already been submitted for this agreement.'
            );
        }

        SigningResponse response = new SigningResponse();
        response.agreementName = agreementRecord.Name;
        response.agreementHtml = agreementRecord.Agreement_HTML__c;
        response.vendorName = agreementRecord.Vendor__r == null
            ? ''
            : agreementRecord.Vendor__r.Name;

        return response;
    }

    @AuraEnabled
    public static void signAgreement(
        Id agreementId,
        String signatureBase64,
        String signedPdfBase64
    ) {
        if (agreementId == null) {
            throw new AuraHandledException(
                'The agreement link is invalid.'
            );
        }

        if (String.isBlank(signatureBase64)) {
            throw new AuraHandledException(
                'Please provide your digital signature.'
            );
        }

        if (String.isBlank(signedPdfBase64)) {
            throw new AuraHandledException(
                'Signed Vendor Agreement PDF is required.'
            );
        }

        Vendor_Agreement__c agreementRecord =
            getAgreementByIdInternal(agreementId);

        if (
            agreementRecord.Agreement_Status__c
            == VendorAgreementConstants.STATUS_SIGNED
        ) {
            throw new AuraHandledException(
                'This Vendor Agreement has already been signed.'
            );
        }

        List<Vendor_Agreement_Signature__c> existingRequests = [
            SELECT Id
            FROM Vendor_Agreement_Signature__c
            WHERE Vendor_Agreement__c = :agreementId
            AND Submission_Status__c IN (
                'Submitted',
                'Processing',
                'Processed'
            )
            LIMIT 1
        ];

        if (!existingRequests.isEmpty()) {
            throw new AuraHandledException(
                'A signature has already been submitted for this agreement.'
            );
        }

        Vendor_Agreement_Signature__c signatureRequest =
            new Vendor_Agreement_Signature__c(
                Vendor_Agreement__c = agreementId,
                Signature_Base64__c = signatureBase64,
                Submission_Status__c = 'Submitted',
                Submitted_Date__c = System.now()
            );

        insert signatureRequest;

        insertPdfChunks(
            signatureRequest.Id,
            signedPdfBase64
        );

        Vendor_Agreement_Signature_Event__e eventRecord =
            new Vendor_Agreement_Signature_Event__e(
                Signature_Request_Id__c =
                    String.valueOf(signatureRequest.Id)
            );

        Database.SaveResult publishResult =
            EventBus.publish(eventRecord);

        if (!publishResult.isSuccess()) {
            throw new AuraHandledException(
                'Signature was saved but could not be queued for processing.'
            );
        }
    }

    private static void insertPdfChunks(
        Id signatureRequestId,
        String signedPdfBase64
    ) {
        if (
            signatureRequestId == null
            || String.isBlank(signedPdfBase64)
        ) {
            return;
        }

        List<Vendor_Agreement_Signature_Chunk__c> chunkRecords =
            new List<Vendor_Agreement_Signature_Chunk__c>();

        Integer sequence = 1;
        Integer startIndex = 0;
        Integer totalLength = signedPdfBase64.length();

        while (startIndex < totalLength) {
            Integer endIndex = Math.min(
                startIndex + PDF_CHUNK_SIZE,
                totalLength
            );

            chunkRecords.add(
                new Vendor_Agreement_Signature_Chunk__c(
                    Signature_Request_Id__c =
                        String.valueOf(signatureRequestId),
                    Sequence__c = sequence,
                    Chunk_Data__c = signedPdfBase64.substring(
                        startIndex,
                        endIndex
                    )
                )
            );

            sequence++;
            startIndex = endIndex;
        }

        if (!chunkRecords.isEmpty()) {
            insert chunkRecords;
        }
    }

    private static Vendor_Agreement__c getAgreementByIdInternal(
        Id agreementId
    ) {
        if (agreementId == null) {
            throw new AuraHandledException(
                'The agreement link is invalid.'
            );
        }

        List<Vendor_Agreement__c> agreements = [
            SELECT Id,
                   Name,
                   Agreement_HTML__c,
                   Agreement_Status__c,
                   Vendor_Opportunity__c,
                   Vendor__r.Name
            FROM Vendor_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        if (agreements.isEmpty()) {
            throw new AuraHandledException(
                'The agreement link is invalid.'
            );
        }

        return agreements[0];
    }
}