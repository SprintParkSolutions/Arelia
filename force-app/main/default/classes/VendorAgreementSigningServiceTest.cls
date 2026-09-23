/**
 * @description Test class for VendorAgreementSigningService.
 * Covers agreement retrieval, signed-agreement validation,
 * duplicate signature validation, null/blank input validations,
 * signature creation, and PDF chunk creation.
 */
@IsTest
@SuppressWarnings(
    'PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.ApexCRUDViolation, PMD.ApexDoc, PMD.TooManyMethods'
)
private class VendorAgreementSigningServiceTest {
    private static final String SUPERVISOR_ALIAS = 'vagsig';
    private static final String VENDOR_NAME =
        'Vendor Agreement Signing Test Vendor';
    private static final String VENDOR_EMAIL =
        'vendor.signing.service.test@example.com';
    private static final String ACCOUNT_NAME =
        'Vendor Agreement Signing Account';
    private static final String OPPORTUNITY_NAME =
        'Vendor Agreement Signing Opportunity';
    private static final String PROJECT_SCOPE = 'Dining Hall';

    private static final String SIGNATURE_BASE64 =
        'data:image/png;base64,test-signature-value';
    private static final String SMALL_SIGNED_PDF_BASE64 =
        'JVBERi0xLjQKJcTl8uXrp/Og0MTGCg==';
    private static final Integer LARGE_PDF_LENGTH = 130000;

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
    private static void getAgreementByIdShouldReturnSigningResponse() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Test.startTest();
        VendorAgreementSigningService.SigningResponse response =
            VendorAgreementSigningService.getAgreementById(agreementRecord.Id);
        Test.stopTest();

        System.assertEquals(
            agreementRecord.Name,
            response.agreementName,
            'Agreement name should be returned.'
        );
        System.assertNotEquals(
            null,
            response.agreementHtml,
            'Agreement HTML should be returned.'
        );
        System.assertEquals(
            VENDOR_NAME,
            response.vendorName,
            'Vendor name should be returned.'
        );
    }

    @IsTest
    private static void getAgreementByIdShouldFailForNullAgreementId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.getAgreementById(null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Null agreement Id should fail.'
        );
    }

    @IsTest
    private static void getAgreementByIdShouldFailWhenAlreadySigned() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SIGNED);

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.getAgreementById(agreementRecord.Id);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Signed agreement should not be opened again.'
        );
    }

    @IsTest
    private static void getAgreementByIdShouldFailWhenSignatureAlreadySubmitted() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        VendorAgreementSigningService.signAgreement(
            agreementRecord.Id,
            SIGNATURE_BASE64,
            SMALL_SIGNED_PDF_BASE64
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.getAgreementById(agreementRecord.Id);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Agreement with submitted signature should fail.'
        );
    }

    @IsTest
    private static void signAgreementShouldFailForNullAgreementId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.signAgreement(
                null,
                SIGNATURE_BASE64,
                SMALL_SIGNED_PDF_BASE64
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Null agreement Id should fail.'
        );
    }

    @IsTest
    private static void signAgreementShouldFailForBlankSignature() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.signAgreement(
                agreementRecord.Id,
                '',
                SMALL_SIGNED_PDF_BASE64
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Blank signature should fail.'
        );
    }

    @IsTest
    private static void signAgreementShouldFailForBlankSignedPdf() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.signAgreement(
                agreementRecord.Id,
                SIGNATURE_BASE64,
                ''
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Blank signed PDF should fail.'
        );
    }

    @IsTest
    private static void signAgreementShouldFailWhenAgreementAlreadySigned() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SIGNED);

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.signAgreement(
                agreementRecord.Id,
                SIGNATURE_BASE64,
                SMALL_SIGNED_PDF_BASE64
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Already signed agreement should fail.'
        );
    }

    @IsTest
    private static void signAgreementShouldFailWhenSignatureAlreadyExists() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        VendorAgreementSigningService.signAgreement(
            agreementRecord.Id,
            SIGNATURE_BASE64,
            SMALL_SIGNED_PDF_BASE64
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            VendorAgreementSigningService.signAgreement(
                agreementRecord.Id,
                SIGNATURE_BASE64,
                SMALL_SIGNED_PDF_BASE64
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Duplicate signature request should fail.'
        );
    }

    @IsTest
    private static void signAgreementShouldCreateSignatureAndSingleChunk() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        Test.startTest();

        VendorAgreementSigningService.signAgreement(
            agreementRecord.Id,
            SIGNATURE_BASE64,
            SMALL_SIGNED_PDF_BASE64
        );

        Test.stopTest();

        Vendor_Agreement_Signature__c signatureRequest =
            getSignatureRequest(agreementRecord.Id);

        System.assert(
            isSubmittedOrProcessing(signatureRequest.Submission_Status__c),
            'Signature request should be Submitted or Processing.'
        );
        System.assertEquals(
            SIGNATURE_BASE64,
            signatureRequest.Signature_Base64__c,
            'Signature Base64 should be stored.'
        );
        System.assertNotEquals(
            null,
            signatureRequest.Submitted_Date__c,
            'Submitted date should be populated.'
        );

        List<Vendor_Agreement_Signature_Chunk__c> chunks =
            getSignatureChunks(signatureRequest.Id);

        System.assertEquals(
            1,
            chunks.size(),
            'Small signed PDF should create one chunk.'
        );
        System.assertEquals(
            1,
            Integer.valueOf(chunks[0].Sequence__c),
            'First chunk sequence should be 1.'
        );
        System.assertEquals(
            SMALL_SIGNED_PDF_BASE64,
            chunks[0].Chunk_Data__c,
            'Chunk data should match signed PDF Base64.'
        );
    }

    @IsTest
    private static void signAgreementShouldCreateMultipleChunks() {
        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(VendorAgreementConstants.STATUS_SENT);

        String largePdfBase64 = buildLargeSignedPdfBase64();

        Test.startTest();

        VendorAgreementSigningService.signAgreement(
            agreementRecord.Id,
            SIGNATURE_BASE64,
            largePdfBase64
        );

        Test.stopTest();

        Vendor_Agreement_Signature__c signatureRequest =
            getSignatureRequest(agreementRecord.Id);

        System.assert(
            isSubmittedOrProcessing(signatureRequest.Submission_Status__c),
            'Signature request should be Submitted or Processing.'
        );

        List<Vendor_Agreement_Signature_Chunk__c> chunks =
            getSignatureChunks(signatureRequest.Id);

        System.assertEquals(
            2,
            chunks.size(),
            'Large signed PDF should create two chunks.'
        );
        System.assertEquals(
            1,
            Integer.valueOf(chunks[0].Sequence__c),
            'First chunk sequence should be 1.'
        );
        System.assertEquals(
            2,
            Integer.valueOf(chunks[1].Sequence__c),
            'Second chunk sequence should be 2.'
        );
        System.assertEquals(
            LARGE_PDF_LENGTH,
            chunks[0].Chunk_Data__c.length()
                + chunks[1].Chunk_Data__c.length(),
            'Total chunk length should match original PDF Base64 length.'
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

        Vendor__c vendorRecord = TestDataUtility.createVendor(
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
        putPicklistIfFieldExists(
            opportunityRecord,
            'Client_Agreement_Status__c',
            'Signed'
        );
        putPicklistIfFieldExists(
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

    private static void putPicklistIfFieldExists(
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

    private static Vendor_Agreement__c getAgreementRecord(Id agreementId) {
        return [
            SELECT Id,
                   Name,
                   Agreement_Status__c,
                   Vendor__c,
                   Vendor__r.Name
            FROM Vendor_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];
    }

    private static Vendor_Agreement_Signature__c getSignatureRequest(
        Id agreementId
    ) {
        return [
            SELECT Id,
                   Signature_Base64__c,
                   Submission_Status__c,
                   Submitted_Date__c
            FROM Vendor_Agreement_Signature__c
            WHERE Vendor_Agreement__c = :agreementId
            LIMIT 1
        ];
    }

    private static List<Vendor_Agreement_Signature_Chunk__c> getSignatureChunks(
        Id signatureRequestId
    ) {
        return [
            SELECT Id,
                   Signature_Request_Id__c,
                   Sequence__c,
                   Chunk_Data__c
            FROM Vendor_Agreement_Signature_Chunk__c
            WHERE Signature_Request_Id__c = :String.valueOf(signatureRequestId)
            ORDER BY Sequence__c ASC
        ];
    }

    private static Boolean isSubmittedOrProcessing(String statusValue) {
        return statusValue == 'Submitted'
            || statusValue == 'Processing';
    }

    private static String buildLargeSignedPdfBase64() {
        String result = '';
        String seedValue = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

        while (result.length() < LARGE_PDF_LENGTH) {
            result += seedValue;
        }

        return result.left(LARGE_PDF_LENGTH);
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