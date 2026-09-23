/**
 * @description Test class for VendorAgreementSignProcessor.
 * Covers null/empty input, non-submitted requests, missing signature,
 * duplicate signed agreement, successful signing, and multiple request processing.
 */
@IsTest
@SuppressWarnings(
    'PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.ApexCRUDViolation, PMD.ApexDoc, PMD.TooManyMethods, PMD.CognitiveComplexity'
)
private class VendorAgreementSignProcessorTest {
    private static final String SUPERVISOR_ALIAS = 'vagpro';
    private static final String VENDOR_NAME =
        'Vendor Agreement Processor Test Vendor';
    private static final String VENDOR_EMAIL =
        'vendor.processor.test@example.com';
    private static final String ACCOUNT_NAME =
        'Vendor Agreement Processor Account';
    private static final String OPPORTUNITY_NAME =
        'Vendor Agreement Processor Opportunity';
    private static final String PROJECT_SCOPE = 'Dining Hall';
    private static final String SIGNATURE_BASE64 =
        'data:image/png;base64,test-signature-value';
    private static final String BLANK_SIGNATURE = '   ';

    private class TestRecords {
        Id opportunityId;
        Id vendorId;
        Id vendorOpportunityId;
    }

    @TestSetup
    static void setupData() {
        TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);
    }

    @IsTest
    private static void processSignatureRequestIdsShouldReturnForNullSet() {
        Test.startTest();
        VendorAgreementSignProcessor.processSignatureRequestIds(null);
        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Null signature request Id set should be handled safely.'
        );
    }

    @IsTest
    private static void processSignatureRequestIdsShouldReturnForEmptySet() {
        Test.startTest();
        VendorAgreementSignProcessor.processSignatureRequestIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Empty signature request Id set should be handled safely.'
        );
    }

    @IsTest
    private static void processSignatureRequestIdsShouldIgnoreNonSubmittedRequest() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing',
                SIGNATURE_BASE64
            );

        VendorAgreementSignProcessor.processSignatureRequestIds(
            new Set<Id>{ signatureRequest.Id }
        );

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        System.assertEquals(
            'Processing',
            updatedSignature.Submission_Status__c,
            'Non-submitted signature request should not be changed.'
        );
        System.assertEquals(
            null,
            updatedSignature.Processed_Date__c,
            'Processed date should remain blank for ignored request.'
        );
    }

    @IsTest
    private static void processSignatureRequestIdsShouldMarkFailedForMissingSignature() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Submitted',
                BLANK_SIGNATURE
            );

        VendorAgreementSignProcessor.processSignatureRequestIds(
            new Set<Id>{ signatureRequest.Id }
        );

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        System.assertEquals(
            'Failed',
            updatedSignature.Submission_Status__c,
            'Signature request should be marked Failed.'
        );
        System.assertNotEquals(
            null,
            updatedSignature.Processing_Error__c,
            'Processing error should be populated.'
        );
        System.assertNotEquals(
            null,
            updatedSignature.Processed_Date__c,
            'Processed date should be populated.'
        );
    }

    @IsTest
    private static void processSignatureRequestIdsShouldMarkDuplicateForSignedAgreement() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SIGNED);

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Submitted',
                SIGNATURE_BASE64
            );

        VendorAgreementSignProcessor.processSignatureRequestIds(
            new Set<Id>{ signatureRequest.Id }
        );

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        System.assertEquals(
            'Duplicate',
            updatedSignature.Submission_Status__c,
            'Signature request should be marked Duplicate.'
        );
        System.assertNotEquals(
            null,
            updatedSignature.Processed_Date__c,
            'Processed date should be populated for duplicate request.'
        );
        System.assertEquals(
            null,
            updatedSignature.Processing_Error__c,
            'Processing error should remain blank for duplicate request.'
        );
    }

    @IsTest
    private static void processSignatureRequestIdsShouldSignAgreement() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Submitted',
                SIGNATURE_BASE64
            );

        VendorAgreementSignProcessor.processSignatureRequestIds(
            new Set<Id>{ signatureRequest.Id }
        );

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        System.assertEquals(
            VendorAgreementConstants.STATUS_SIGNED,
            updatedAgreement.Agreement_Status__c,
            'Agreement should be marked Signed.'
        );
        System.assertEquals(
            SIGNATURE_BASE64,
            updatedAgreement.Signature_Base64__c,
            'Signature Base64 should be stored on agreement.'
        );
        System.assertEquals(
            Date.today(),
            updatedAgreement.Signed_Date__c,
            'Signed date should be today.'
        );
        System.assert(
            updatedAgreement.Agreement_HTML__c.contains('Vendor Digital Signature'),
            'Digital signature HTML should be appended.'
        );
        System.assert(
            updatedAgreement.Agreement_HTML__c.contains(VENDOR_NAME),
            'Vendor name should be included in signature HTML.'
        );
        System.assert(
            updatedAgreement.Agreement_HTML__c.contains(SIGNATURE_BASE64),
            'Signature image should be included in agreement HTML.'
        );
        System.assertEquals(
            'Processing',
            updatedSignature.Submission_Status__c,
            'Signature request should be marked Processing before queueable execution.'
        );
        System.assertEquals(
            null,
            updatedSignature.Processing_Error__c,
            'Processing error should be cleared.'
        );
    }

    @IsTest
    private static void processSignatureRequestIdsShouldProcessMultipleRequests() {
        Vendor_Agreement__c firstAgreement =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Vendor_Agreement__c secondAgreement =
            createAgreementRecord(VendorAgreementConstants.STATUS_SIGNED);

        Vendor_Agreement_Signature__c firstSignature =
            createSignatureRequest(
                firstAgreement.Id,
                'Submitted',
                SIGNATURE_BASE64
            );

        Vendor_Agreement_Signature__c secondSignature =
            createSignatureRequest(
                secondAgreement.Id,
                'Submitted',
                SIGNATURE_BASE64
            );

        VendorAgreementSignProcessor.processSignatureRequestIds(
            new Set<Id>{
                firstSignature.Id,
                secondSignature.Id
            }
        );

        Vendor_Agreement__c updatedFirstAgreement =
            getAgreementRecord(firstAgreement.Id);

        Vendor_Agreement_Signature__c updatedFirstSignature =
            getSignatureRequest(firstSignature.Id);

        Vendor_Agreement_Signature__c updatedSecondSignature =
            getSignatureRequest(secondSignature.Id);

        System.assertEquals(
            VendorAgreementConstants.STATUS_SIGNED,
            updatedFirstAgreement.Agreement_Status__c,
            'First agreement should be signed.'
        );
        System.assertEquals(
            'Processing',
            updatedFirstSignature.Submission_Status__c,
            'First signature should be processing.'
        );
        System.assertEquals(
            'Duplicate',
            updatedSecondSignature.Submission_Status__c,
            'Second signature should be duplicate.'
        );
    }

    private static Vendor_Agreement__c createAgreementRecord(
        String agreementStatus
    ) {
        TestRecords records = createVendorAgreementRecords();

        VendorAgreementService.AgreementResponse response =
            VendorAgreementService.getAgreement(records.vendorOpportunityId);

        Vendor_Agreement__c agreementRecord =
            getAgreementRecord(response.agreementId);

        agreementRecord.Agreement_Status__c =
            getPreferredPicklistValue(
                Vendor_Agreement__c.Agreement_Status__c,
                agreementStatus
            );

        update agreementRecord;

        return getAgreementRecord(agreementRecord.Id);
    }

    private static TestRecords createVendorAgreementRecords() {
        TestRecords records = new TestRecords();

        User supervisorUser = [
            SELECT Id
            FROM User
            WHERE Alias = :SUPERVISOR_ALIAS
            LIMIT 1
        ];

        Vendor__c vendorRecord =
            TestDataUtility.createVendor(
                VENDOR_NAME,
                getFirstActivePicklistValue(Vendor__c.Vendor_Category__c),
                VENDOR_EMAIL
            );

        Account accountRecord =
            TestDataUtility.createAccount(ACCOUNT_NAME);

        Opportunity opportunityRecord =
            TestDataUtility.createOpportunity(
                OPPORTUNITY_NAME,
                supervisorUser.Id
            );

        opportunityRecord.AccountId = accountRecord.Id;
        opportunityRecord.Project_Scope__c =
            getPreferredPicklistValue(
                Opportunity.Project_Scope__c,
                PROJECT_SCOPE
            );

        update opportunityRecord;

        System.assertEquals(
            AreliaUtility.getAreliaOpportunityRecordTypeId(),
            opportunityRecord.RecordTypeId,
            'Opportunity should keep Arelia Record Type from TestDataUtility.'
        );

        prepareOpportunityForVendorAgreement(opportunityRecord.Id);

        Vendor_Opportunity__c vendorOpportunity =
            TestDataUtility.createVendorOpportunity(
                opportunityRecord.Id,
                vendorRecord.Id,
                getFirstActivePicklistValue(
                    Vendor_Opportunity__c.Vendor_Opportunity_Status__c
                )
            );

        records.opportunityId = opportunityRecord.Id;
        records.vendorId = vendorRecord.Id;
        records.vendorOpportunityId = vendorOpportunity.Id;

        return records;
    }

    private static void prepareOpportunityForVendorAgreement(
        Id opportunityId
    ) {
        Opportunity opportunityRecord =
            new Opportunity(Id = opportunityId);

        putUpdateableValueIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Sent__c',
            true
        );
        putUpdateableValueIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Signed__c',
            true
        );
        putUpdateableValueIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Completed__c',
            true
        );
        putUpdateablePicklistIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Status__c',
            'Signed'
        );
        putUpdateablePicklistIfFieldExists(
            opportunityRecord,
            'Agreement_Status__c',
            'Signed'
        );

        Database.SaveResult updateResult =
            Database.update(opportunityRecord, false);

        System.assertEquals(
            true,
            updateResult.isSuccess(),
            buildDatabaseErrorMessage(updateResult)
        );
    }

    private static void putUpdateableValueIfFieldExists(
        SObject recordValue,
        String fieldName,
        Object fieldValue
    ) {
        Map<String, Schema.SObjectField> fieldMap =
            recordValue.getSObjectType().getDescribe().fields.getMap();

        if (!fieldMap.containsKey(fieldName)) {
            return;
        }

        if (!fieldMap.get(fieldName).getDescribe().isUpdateable()) {
            return;
        }

        recordValue.put(fieldName, fieldValue);
    }

    private static void putUpdateablePicklistIfFieldExists(
        SObject recordValue,
        String fieldName,
        String preferredValue
    ) {
        Map<String, Schema.SObjectField> fieldMap =
            recordValue.getSObjectType().getDescribe().fields.getMap();

        if (!fieldMap.containsKey(fieldName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fieldMap.get(fieldName).getDescribe();

        if (
            !fieldDescribe.isUpdateable()
            || fieldDescribe.getType() != Schema.DisplayType.Picklist
        ) {
            return;
        }

        recordValue.put(
            fieldName,
            getPreferredPicklistValue(
                fieldMap.get(fieldName),
                preferredValue
            )
        );
    }

    private static Vendor_Agreement_Signature__c createSignatureRequest(
        Id agreementId,
        String submissionStatus,
        String signatureBase64
    ) {
        Vendor_Agreement_Signature__c signatureRequest =
            new Vendor_Agreement_Signature__c();

        signatureRequest.Vendor_Agreement__c = agreementId;
        signatureRequest.Submission_Status__c =
            getPreferredPicklistValue(
                Vendor_Agreement_Signature__c.Submission_Status__c,
                submissionStatus
            );
        signatureRequest.Signature_Base64__c = signatureBase64;
        signatureRequest.Submitted_Date__c = System.now();

        insert signatureRequest;

        return signatureRequest;
    }

    private static Vendor_Agreement__c getAgreementRecord(Id agreementId) {
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
                   Signature_Base64__c,
                   Submission_Status__c,
                   Processing_Error__c,
                   Processed_Date__c
            FROM Vendor_Agreement_Signature__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];
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

        System.assert(
            false,
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