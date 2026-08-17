/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementSignProcessor
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

public without sharing class VendorAgreementSignProcessor {

    public static void processSignatureRequestIds(
        Set<Id> signatureRequestIds
    ) {
        if (
            signatureRequestIds == null
            || signatureRequestIds.isEmpty()
        ) {
            return;
        }

        List<Vendor_Agreement_Signature__c> signatureRequests = [
            SELECT Id,
                   Vendor_Agreement__c,
                   Signature_Base64__c,
                   Submission_Status__c
            FROM Vendor_Agreement_Signature__c
            WHERE Id IN :signatureRequestIds
        ];

        for (
            Vendor_Agreement_Signature__c signatureRequest
            : signatureRequests
        ) {
            processSingleSignatureRequest(signatureRequest);
        }
    }

    private static void processSingleSignatureRequest(
        Vendor_Agreement_Signature__c signatureRequest
    ) {
        try {
            if (
                signatureRequest.Submission_Status__c
                != 'Submitted'
            ) {
                return;
            }

            update new Vendor_Agreement_Signature__c(
                Id = signatureRequest.Id,
                Submission_Status__c = 'Processing',
                Processing_Error__c = null
            );

            if (
                signatureRequest.Vendor_Agreement__c == null
                || String.isBlank(
                    signatureRequest.Signature_Base64__c
                )
            ) {
                markFailed(
                    signatureRequest.Id,
                    'Vendor Agreement and signature are required.'
                );

                return;
            }

            List<Vendor_Agreement__c> agreements = [
                SELECT Id,
                       Name,
                       Agreement_HTML__c,
                       Agreement_Status__c,
                       Vendor_Opportunity__c,
                       Vendor__r.Name
                FROM Vendor_Agreement__c
                WHERE Id = :signatureRequest.Vendor_Agreement__c
                LIMIT 1
            ];

            if (agreements.isEmpty()) {
                markFailed(
                    signatureRequest.Id,
                    'Vendor Agreement record was not found.'
                );

                return;
            }

            Vendor_Agreement__c agreementRecord = agreements[0];

            if (
                agreementRecord.Agreement_Status__c
                == VendorAgreementConstants.STATUS_SIGNED
            ) {
                update new Vendor_Agreement_Signature__c(
                    Id = signatureRequest.Id,
                    Submission_Status__c = 'Duplicate',
                    Processed_Date__c = System.now(),
                    Processing_Error__c = null
                );

                return;
            }

            String vendorName = agreementRecord.Vendor__r == null
                ? ''
                : VendorAgreementUtil.escapeHtml(
                    agreementRecord.Vendor__r.Name
                );

            String signedHtml =
                agreementRecord.Agreement_HTML__c
                + buildSignatureHtml(
                    vendorName,
                    signatureRequest.Signature_Base64__c
                );

            update new Vendor_Agreement__c(
                Id = agreementRecord.Id,
                Signature_Base64__c =
                    signatureRequest.Signature_Base64__c,
                Agreement_HTML__c = signedHtml,
                Agreement_Status__c =
                    VendorAgreementConstants.STATUS_SIGNED,
                Signed_Date__c = Date.today()
            );

            System.enqueueJob(
                new VendorAgreementSignedJob(
                    agreementRecord.Id,
                    signatureRequest.Id
                )
            );
        } catch (Exception exceptionValue) {
            markFailed(
                signatureRequest.Id,
                exceptionValue.getMessage()
            );
        }
    }

    private static String buildSignatureHtml(
        String vendorName,
        String signatureBase64
    ) {
        return
            '<div class="digital-signature">'
            + '<h2>Vendor Digital Signature</h2>'
            + '<p><strong>Vendor:</strong> '
            + vendorName
            + '</p>'
            + '<p><strong>Signed Date:</strong> '
            + String.valueOf(Date.today())
            + '</p>'
            + '<img style="width:240px;height:100px;" src="'
            + signatureBase64
            + '" />'
            + '</div>';
    }

    private static void markFailed(
        Id signatureRequestId,
        String errorMessage
    ) {
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