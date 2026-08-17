/**
 * @description Test class for VendorAgreementSignedJob.
 * Covers signed PDF creation, data URL cleanup, multiple chunks,
 * blank chunks, missing chunks, invalid base64, non-signed agreement,
 * null signature id, missing agreement id, and Vendor Opportunity signed flag update.
 */
@IsTest
@SuppressWarnings(
    'PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.CognitiveComplexity, PMD.ApexCRUDViolation, PMD.ApexDoc'
)
private class VendorAgreementSignedJobTest {
    private static final String SUPERVISOR_ALIAS = 'vasjob';
    private static final String VENDOR_NAME =
        'Vendor Agreement Signed Job Test Vendor';
    private static final String VENDOR_EMAIL =
        'vendor.signed.job.test@example.com';
    private static final String AGREEMENT_HTML =
        '<div><h1>Vendor Agreement</h1><p>Signed agreement content</p></div>';
    private static final String PDF_TEXT =
        'Signed Vendor Agreement PDF Content';
    private static final String DATA_URL_PREFIX =
        'data:application/pdf;base64,';
    private static final String ACCOUNT_NAME =
        'Signed Job Vendor Agreement Account';
    private static final String OPPORTUNITY_NAME =
        'Signed Job Vendor Agreement Opportunity';
    private static final String PROJECT_SCOPE = 'Dining Hall';

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
    private static void executeShouldCreateSignedFileBeforeEmailFailureOrProcess() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        createPdfChunk(
            signatureRequest.Id,
            1,
            EncodingUtil.base64Encode(Blob.valueOf(PDF_TEXT))
        );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        Assert.isNotNull(
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should be populated before email processing.'
        );
        Assert.isTrue(
            isProcessedOrFailed(updatedSignature.Submission_Status__c),
            'Signature should be Processed if email config works, otherwise Failed.'
        );
        Assert.isNotNull(
            updatedSignature.Processed_Date__c,
            'Processed date should be populated.'
        );
    }

    @IsTest
    private static void executeShouldHandleDataUrlBase64Prefix() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        createPdfChunk(
            signatureRequest.Id,
            1,
            DATA_URL_PREFIX
                + EncodingUtil.base64Encode(Blob.valueOf(PDF_TEXT))
        );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        Assert.isNotNull(
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should be populated after Data URL Base64 cleanup.'
        );
        Assert.isTrue(
            isProcessedOrFailed(updatedSignature.Submission_Status__c),
            'Signature should be Processed or Failed depending on email configuration.'
        );
    }

    @IsTest
    private static void executeShouldRebuildPdfFromMultipleChunks() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        String fullBase64 =
            EncodingUtil.base64Encode(Blob.valueOf(PDF_TEXT));

        createPdfChunk(
            signatureRequest.Id,
            1,
            fullBase64.left(10)
        );
        createPdfChunk(
            signatureRequest.Id,
            2,
            fullBase64.substring(10)
        );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Assert.isNotNull(
            updatedAgreement.Signed_File_Id__c,
            'Signed file should be created from multiple chunks.'
        );
    }

    @IsTest
    private static void executeShouldIgnoreBlankChunksAndUseValidChunk() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        createPdfChunk(
            signatureRequest.Id,
            1,
            ''
        );
        createPdfChunk(
            signatureRequest.Id,
            2,
            EncodingUtil.base64Encode(Blob.valueOf(PDF_TEXT))
        );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Assert.isNotNull(
            updatedAgreement.Signed_File_Id__c,
            'Signed file should be created when at least one chunk has data.'
        );
    }

    @IsTest
    private static void executeShouldMarkFailedWhenAgreementIsNotSigned() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_DRAFT
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        createPdfChunk(
            signatureRequest.Id,
            1,
            EncodingUtil.base64Encode(Blob.valueOf(PDF_TEXT))
        );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        Assert.areEqual(
            'Failed',
            updatedSignature.Submission_Status__c,
            'Signature request should be marked Failed.'
        );
        Assert.isNotNull(
            updatedSignature.Processing_Error__c,
            'Processing error should be populated.'
        );
        Assert.isNotNull(
            updatedSignature.Processed_Date__c,
            'Processed date should be populated.'
        );
    }

    @IsTest
    private static void executeShouldMarkFailedWhenPdfChunksAreMissing() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        Assert.areEqual(
            'Failed',
            updatedSignature.Submission_Status__c,
            'Signature request should be marked Failed when chunks are missing.'
        );
        Assert.isNotNull(
            updatedSignature.Processing_Error__c,
            'Processing error should be populated.'
        );
    }

    @IsTest
    private static void executeShouldMarkFailedWhenPdfBase64IsInvalid() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        createPdfChunk(
            signatureRequest.Id,
            1,
            'invalid-base64-value'
        );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        Assert.areEqual(
            'Failed',
            updatedSignature.Submission_Status__c,
            'Signature request should be marked Failed for invalid Base64.'
        );
        Assert.isNotNull(
            updatedSignature.Processing_Error__c,
            'Processing error should be populated.'
        );
    }

    @IsTest
    private static void executeShouldHandleNullSignatureRequestId() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            null
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Assert.areEqual(
            null,
            updatedAgreement.Signed_File_Id__c,
            'Signed file should not be created when signature request Id is null.'
        );
    }

    @IsTest
    private static void executeShouldHandleMissingAgreementId() {
        Vendor_Agreement__c validAgreement =
            createAgreementRecord(
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                validAgreement.Id,
                'Processing'
            );

        Test.startTest();

        new VendorAgreementSignedJob(
            buildFakeVendorAgreementId(),
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Agreement_Signature__c updatedSignature =
            getSignatureRequest(signatureRequest.Id);

        Assert.areEqual(
            'Failed',
            updatedSignature.Submission_Status__c,
            'Signature request should be marked Failed for missing agreement.'
        );
        Assert.isNotNull(
            updatedSignature.Processing_Error__c,
            'Processing error should be populated.'
        );
    }

    @IsTest
    private static void executeShouldUpdateVendorOpportunitySignedFlag() {
        TestRecords records =
            createVendorAgreementRecords();

        Vendor_Agreement__c agreementRecord =
            createAgreementFromService(
                records,
                VendorAgreementConstants.STATUS_SIGNED
            );

        Vendor_Agreement_Signature__c signatureRequest =
            createSignatureRequest(
                agreementRecord.Id,
                'Processing'
            );

        createPdfChunk(
            signatureRequest.Id,
            1,
            EncodingUtil.base64Encode(Blob.valueOf(PDF_TEXT))
        );

        Test.startTest();

        new VendorAgreementSignedJob(
            agreementRecord.Id,
            signatureRequest.Id
        ).execute(null);

        Test.stopTest();

        Vendor_Opportunity__c updatedVendorOpportunity = [
            SELECT Vendor_Agreement_Signed__c
            FROM Vendor_Opportunity__c
            WHERE Id = :records.vendorOpportunityId
            LIMIT 1
        ];

        Vendor_Agreement__c updatedAgreement =
            getAgreementRecord(agreementRecord.Id);

        Assert.areEqual(
            true,
            updatedVendorOpportunity.Vendor_Agreement_Signed__c,
            'Vendor Agreement Signed flag should be updated on Vendor Opportunity.'
        );
        Assert.isNotNull(
            updatedAgreement.Signed_File_Id__c,
            'Signed file Id should be populated.'
        );
    }

    private static Vendor_Agreement__c createAgreementRecord(
        String agreementStatus
    ) {
        TestRecords records =
            createVendorAgreementRecords();

        return createAgreementFromService(
            records,
            agreementStatus
        );
    }

    private static Vendor_Agreement__c createAgreementFromService(
        TestRecords records,
        String agreementStatus
    ) {
        VendorAgreementService.AgreementResponse response =
            VendorAgreementService.getAgreement(
                records.vendorOpportunityId
            );

        Vendor_Agreement__c agreementRecord =
            getAgreementRecord(response.agreementId);

        agreementRecord.Agreement_Status__c =
            getPreferredPicklistValue(
                Vendor_Agreement__c.Agreement_Status__c,
                agreementStatus
            );

        agreementRecord.Agreement_HTML__c = AGREEMENT_HTML;
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
            createVendorRecord();

        Opportunity opportunityRecord =
            createAreliaOpportunity(supervisorUser.Id);

        prepareOpportunityForVendorOpportunity(
            opportunityRecord.Id
        );

        Vendor_Opportunity__c vendorOpportunity =
            createVendorOpportunityRecord(
                opportunityRecord.Id,
                vendorRecord.Id
            );

        records.opportunityId = opportunityRecord.Id;
        records.vendorId = vendorRecord.Id;
        records.vendorOpportunityId = vendorOpportunity.Id;

        return records;
    }

    private static Vendor__c createVendorRecord() {
        Vendor__c vendorRecord =
            TestDataUtility.createVendor(
                VENDOR_NAME,
                getFirstActivePicklistValue(
                    Vendor__c.Vendor_Category__c
                ),
                VENDOR_EMAIL
            );

        return vendorRecord;
    }

    private static Opportunity createAreliaOpportunity(
        Id supervisorUserId
    ) {
        Account accountRecord =
            TestDataUtility.createAccount(ACCOUNT_NAME);

        Opportunity opportunityRecord =
            TestDataUtility.createOpportunity(
                OPPORTUNITY_NAME,
                supervisorUserId
            );

        opportunityRecord.AccountId = accountRecord.Id;
        putPreferredPicklistIfFieldExists(
            opportunityRecord,
            'Project_Scope__c',
            PROJECT_SCOPE
        );

        update opportunityRecord;

        Assert.areEqual(
            AreliaUtility.getAreliaOpportunityRecordTypeId(),
            opportunityRecord.RecordTypeId,
            'Opportunity should keep Arelia Record Type from TestDataUtility.'
        );

        return opportunityRecord;
    }

    private static Vendor_Opportunity__c createVendorOpportunityRecord(
        Id opportunityId,
        Id vendorId
    ) {
        Vendor_Opportunity__c vendorOpportunity =
            TestDataUtility.createVendorOpportunity(
                opportunityId,
                vendorId,
                getFirstActivePicklistValue(
                    Vendor_Opportunity__c.Vendor_Opportunity_Status__c
                )
            );

        Assert.isNotNull(
            vendorOpportunity.Id,
            'Vendor Opportunity should be created.'
        );

        return vendorOpportunity;
    }

    private static void prepareOpportunityForVendorOpportunity(
        Id opportunityId
    ) {
        Opportunity opportunityRecord =
            new Opportunity(Id = opportunityId);

        putValueIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Sent__c',
            true
        );
        putValueIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Signed__c',
            true
        );
        putValueIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Completed__c',
            true
        );
        putPreferredPicklistIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Status__c',
            'Signed'
        );
        putPreferredPicklistIfFieldExists(
            opportunityRecord,
            'Agreement_Status__c',
            'Signed'
        );

        Database.SaveResult updateResult =
            Database.update(opportunityRecord, false);

        Assert.isTrue(
            updateResult.isSuccess(),
            buildDatabaseErrorMessage(updateResult)
        );
    }

    private static Vendor_Agreement_Signature__c createSignatureRequest(
        Id agreementId,
        String submissionStatus
    ) {
        Vendor_Agreement_Signature__c signatureRequest =
            new Vendor_Agreement_Signature__c();

        signatureRequest.Vendor_Agreement__c = agreementId;
        signatureRequest.Submission_Status__c =
            getPreferredPicklistValue(
                Vendor_Agreement_Signature__c.Submission_Status__c,
                submissionStatus
            );
        signatureRequest.Signature_Base64__c =
            'data:image/png;base64,test-signature';
        signatureRequest.Submitted_Date__c = System.now();

        insert signatureRequest;

        return signatureRequest;
    }

    private static void createPdfChunk(
        Id signatureRequestId,
        Integer sequence,
        String chunkData
    ) {
        Vendor_Agreement_Signature_Chunk__c chunkRecord =
            new Vendor_Agreement_Signature_Chunk__c();

        chunkRecord.Signature_Request_Id__c =
            String.valueOf(signatureRequestId);
        chunkRecord.Sequence__c = sequence;
        chunkRecord.Chunk_Data__c = chunkData;

        insert chunkRecord;
    }

    private static Vendor_Agreement__c getAgreementRecord(
        Id agreementId
    ) {
        return [
            SELECT Id,
                   Name,
                   Agreement_HTML__c,
                   Agreement_Status__c,
                   Vendor_Opportunity__c,
                   Signed_File_Id__c
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
                   Submission_Status__c,
                   Processing_Error__c,
                   Processed_Date__c
            FROM Vendor_Agreement_Signature__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];
    }

    private static Boolean isProcessedOrFailed(String statusValue) {
        return statusValue == 'Processed'
            || statusValue == 'Failed';
    }

    private static void putValueIfFieldExists(
        SObject recordValue,
        String fieldName,
        Object fieldValue
    ) {
        Map<String, Schema.SObjectField> fieldMap =
            recordValue.getSObjectType().getDescribe().fields.getMap();

        if (fieldMap.containsKey(fieldName)) {
            recordValue.put(fieldName, fieldValue);
        }
    }

    private static void putPreferredPicklistIfFieldExists(
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

        if (fieldDescribe.getType() != Schema.DisplayType.Picklist) {
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

    private static Id buildFakeVendorAgreementId() {
        return Id.valueOf(
            Vendor_Agreement__c.SObjectType
                .getDescribe()
                .getKeyPrefix()
                + '000000000001'
        );
    }
}