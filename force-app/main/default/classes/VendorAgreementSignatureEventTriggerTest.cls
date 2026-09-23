/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementSignatureEventTriggerTest
 * Author          : <YourName>
 * Created Date    : Jul 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 10, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * @description
 * Test class for VendorAgreementSignatureEventTrigger.
 *
 * Covers:
 * - Blank platform event Signature_Request_Id__c handling
 * - Invalid platform event Signature_Request_Id__c handling
 * - Valid platform event Signature_Request_Id__c processing
 * - VendorAgreementSignProcessor invocation from trigger
 */
/**
 * @description
 * Test class for VendorAgreementSignatureEventTrigger.
 *
 * Covers:
 * - Blank platform event Signature_Request_Id__c handling
 * - Invalid platform event Signature_Request_Id__c handling
 * - Valid platform event Signature_Request_Id__c processing
 * - VendorAgreementSignProcessor invocation from trigger
 */
@IsTest
@SuppressWarnings(
    'PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts'
)
private class VendorAgreementSignatureEventTriggerTest {

    private static final String VENDOR_NAME =
        'Vendor Agreement Event Trigger Test Vendor';
    private static final String VENDOR_EMAIL =
        'vendor.event.trigger.test@example.com';
    private static final String AGREEMENT_HTML =
        '<div><h1>Vendor Agreement</h1><p>Event trigger test content</p></div>';
    private static final String SIGNATURE_BASE64 =
        'data:image/png;base64,test-signature-value';
    private static final String INVALID_SIGNATURE_REQUEST_ID =
        'badid';

    @IsTest
    private static void triggerShouldProcessValidSignatureRequestId() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SENT
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Submitted',
                SIGNATURE_BASE64
            );

        Vendor_Agreement_Signature_Event__e eventRecord =
            new Vendor_Agreement_Signature_Event__e(
                Signature_Request_Id__c =
                    String.valueOf(signatureRequest.Id)
            );

        Test.startTest();

        Database.SaveResult publishResult =
            EventBus.publish(eventRecord);

        Test.stopTest();

        Assert.isTrue(
            publishResult.isSuccess(),
            buildDatabaseErrorMessage(publishResult)
        );

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        Assert.areEqual(
            VendorAgreementConstants.STATUS_SIGNED,
            updatedAgreement.Agreement_Status__c,
            'Agreement should be marked Signed by processor.'
        );
        Assert.areEqual(
            SIGNATURE_BASE64,
            updatedAgreement.Signature_Base64__c,
            'Signature Base64 should be copied to agreement.'
        );
        Assert.isNotNull(
            updatedAgreement.Signed_Date__c,
            'Signed date should be populated after successful signing.'
        );
        Assert.isTrue(
            updatedAgreement.Agreement_HTML__c.contains(
                'Vendor Digital Signature'
            ),
            'Digital signature HTML should be appended to agreement.'
        );
        Assert.isTrue(
            isProcessedProcessingOrFailed(
                updatedSignature.Submission_Status__c
            ),
            'Signature request should be processed, processing, or failed by downstream queueable.'
        );
    }

    @IsTest
    private static void triggerShouldIgnoreBlankSignatureRequestId() {
        Vendor_Agreement_Signature_Event__e eventRecord =
            new Vendor_Agreement_Signature_Event__e(
                Signature_Request_Id__c = ''
            );

        Test.startTest();

        Database.SaveResult publishResult =
            EventBus.publish(eventRecord);

        Test.stopTest();

        Assert.isTrue(
            publishResult.isSuccess(),
            buildDatabaseErrorMessage(publishResult)
        );
    }

    @IsTest
    private static void triggerShouldIgnoreInvalidSignatureRequestId() {
        Vendor_Agreement_Signature_Event__e eventRecord =
            new Vendor_Agreement_Signature_Event__e(
                Signature_Request_Id__c = INVALID_SIGNATURE_REQUEST_ID
            );

        Test.startTest();

        Database.SaveResult publishResult =
            EventBus.publish(eventRecord);

        Test.stopTest();

        Assert.isTrue(
            publishResult.isSuccess(),
            buildDatabaseErrorMessage(publishResult)
        );
    }

    @IsTest
    private static void triggerShouldHandleMixedEvents() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SENT
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Submitted',
                SIGNATURE_BASE64
            );

        List<Vendor_Agreement_Signature_Event__e> eventRecords =
            new List<Vendor_Agreement_Signature_Event__e>{
                new Vendor_Agreement_Signature_Event__e(
                    Signature_Request_Id__c = ''
                ),
                new Vendor_Agreement_Signature_Event__e(
                    Signature_Request_Id__c =
                        INVALID_SIGNATURE_REQUEST_ID
                ),
                new Vendor_Agreement_Signature_Event__e(
                    Signature_Request_Id__c =
                        String.valueOf(signatureRequest.Id)
                )
            };

        Test.startTest();

        List<Database.SaveResult> publishResults =
            EventBus.publish(eventRecords);

        Test.stopTest();

        Assert.areEqual(
            eventRecords.size(),
            publishResults.size(),
            'All platform events should return publish results.'
        );

        for (Database.SaveResult publishResult : publishResults) {
            Assert.isTrue(
                publishResult.isSuccess(),
                buildDatabaseErrorMessage(publishResult)
            );
        }

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Assert.areEqual(
            VendorAgreementConstants.STATUS_SIGNED,
            updatedAgreement.Agreement_Status__c,
            'Valid event in mixed event batch should still be processed.'
        );
    }

    private static Vendor_Agreement__c createAgreementRecord(
        String agreementStatus
    ) {
        Vendor__c vendorRecord =
            createVendorRecord();

        Vendor_Agreement__c agreementRecord =
            new Vendor_Agreement__c(
                Vendor__c = vendorRecord.Id,
                Vendor_Email__c = VENDOR_EMAIL,
                Agreement_HTML__c = AGREEMENT_HTML,
                Agreement_Status__c = getPreferredPicklistValue(
                    Vendor_Agreement__c.Agreement_Status__c,
                    agreementStatus
                )
            );

        insert agreementRecord;

        return getAgreementRecord(agreementRecord.Id);
    }

    private static Vendor__c createVendorRecord() {
        Vendor__c vendorRecord =
            new Vendor__c(
                Name = VENDOR_NAME,
                Email__c = VENDOR_EMAIL,
                Vendor_Category__c = getFirstActivePicklistValue(
                    Vendor__c.Vendor_Category__c
                ),
                Vendor_Status__c = getFirstActivePicklistValue(
                    Vendor__c.Vendor_Status__c
                ),
                Average_Efficiency__c = 95.5
            );

        insert vendorRecord;

        return vendorRecord;
    }

    private static Vendor_Agreement_Signature__c createSignatureRequest(
        Id agreementId,
        String submissionStatus,
        String signatureBase64
    ) {
        Vendor_Agreement_Signature__c signatureRequest =
            new Vendor_Agreement_Signature__c(
                Vendor_Agreement__c = agreementId,
                Signature_Base64__c = signatureBase64,
                Submission_Status__c = submissionStatus,
                Submitted_Date__c = System.now()
            );

        insert signatureRequest;

        return signatureRequest;
    }

    private static Vendor_Agreement__c getAgreementRecord(
        Id agreementId
    ) {
        return [
            SELECT Id,
                   Name,
                   Agreement_HTML__c,
                   Agreement_Status__c,
                   Signature_Base64__c,
                   Signed_Date__c,
                   Vendor__c,
                   Vendor__r.Name
            FROM Vendor_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];
    }

    private static Vendor_Agreement_Signature__c getSignatureRequest(
        Id signatureRequestId
    ) {
        return [
            SELECT Id,
                   Vendor_Agreement__c,
                   Signature_Base64__c,
                   Submission_Status__c,
                   Processing_Error__c,
                   Processed_Date__c
            FROM Vendor_Agreement_Signature__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];
    }

    private static Boolean isProcessedProcessingOrFailed(
        String statusValue
    ) {
        return statusValue == 'Processing'
            || statusValue == 'Processed'
            || statusValue == 'Failed';
    }

    private static String getPreferredPicklistValue(
        Schema.SObjectField fieldToken,
        String preferredValue
    ) {
        List<Schema.PicklistEntry> picklistValues =
            fieldToken.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry picklistValue : picklistValues) {
            if (
                picklistValue.isActive()
                && picklistValue.getValue() == preferredValue
            ) {
                return picklistValue.getValue();
            }
        }

        return getFirstActivePicklistValue(fieldToken);
    }

    private static String getFirstActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {
        List<Schema.PicklistEntry> picklistValues =
            fieldToken.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry picklistValue : picklistValues) {
            if (picklistValue.isActive()) {
                return picklistValue.getValue();
            }
        }

        Assert.fail(
            'No active picklist value found for '
                + fieldToken.getDescribe().getName()
        );

        return null;
    }

    private static String buildDatabaseErrorMessage(
        Database.SaveResult saveResult
    ) {
        if (
            saveResult == null
            || saveResult.isSuccess()
            || saveResult.getErrors().isEmpty()
        ) {
            return 'DML operation failed.';
        }

        return saveResult.getErrors()[0].getMessage();
    }
}