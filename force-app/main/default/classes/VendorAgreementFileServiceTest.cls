/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementFileServiceTest
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
 * Test class for VendorAgreementFileService.
 *
 * Covers:
 * - Unsigned PDF file creation
 * - Signed PDF file creation
 * - Signed PDF creation from Blob
 * - Latest ContentVersion VersionData retrieval
 * - Blank ContentDocumentId validation
 * - Missing ContentVersion validation
 * - Null agreement validation
 * - Empty signed PDF Blob validation
 */
@IsTest
@SuppressWarnings('PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts')
private class VendorAgreementFileServiceTest {

    private static final String AGREEMENT_NAME = 'VA-TEST-0001';
    private static final String TEST_PDF_CONTENT =
        'Signed Vendor Agreement Test PDF';

    @IsTest
    private static void createUnsignedAgreementPdfShouldCreateContentDocument() {
        Vendor_Agreement__c agreementRecord =
            buildAgreementRecord();

        Test.startTest();

        Id contentDocumentId =
            VendorAgreementFileService.createUnsignedAgreementPdf(
                agreementRecord
            );

        Test.stopTest();

        Assert.isNotNull(
            contentDocumentId,
            'Unsigned ContentDocument Id should be returned.'
        );

        ContentVersion versionRecord =
            getLatestContentVersion(contentDocumentId);

        Assert.areEqual(
            VendorAgreementConstants.UNSIGNED_FILE_PREFIX
                + AGREEMENT_NAME,
            versionRecord.Title,
            'Unsigned PDF title should use unsigned prefix.'
        );
        Assert.areEqual(
            VendorAgreementConstants.UNSIGNED_FILE_PREFIX
                + AGREEMENT_NAME
                + VendorAgreementConstants.PDF_EXTENSION,
            versionRecord.PathOnClient,
            'Unsigned PDF file path should be generated correctly.'
        );
        Assert.areEqual(
            'Vendor Agreement Test PDF',
            versionRecord.VersionData.toString(),
            'Test PDF Blob should be saved as ContentVersion data.'
        );
    }

    @IsTest
    private static void createSignedAgreementPdfShouldCreateContentDocument() {
        Vendor_Agreement__c agreementRecord =
            buildAgreementRecord();

        Test.startTest();

        Id contentDocumentId =
            VendorAgreementFileService.createSignedAgreementPdf(
                agreementRecord
            );

        Test.stopTest();

        Assert.isNotNull(
            contentDocumentId,
            'Signed ContentDocument Id should be returned.'
        );

        ContentVersion versionRecord =
            getLatestContentVersion(contentDocumentId);

        Assert.areEqual(
            VendorAgreementConstants.SIGNED_FILE_PREFIX
                + AGREEMENT_NAME,
            versionRecord.Title,
            'Signed PDF title should use signed prefix.'
        );
        Assert.areEqual(
            VendorAgreementConstants.SIGNED_FILE_PREFIX
                + AGREEMENT_NAME
                + VendorAgreementConstants.PDF_EXTENSION,
            versionRecord.PathOnClient,
            'Signed PDF file path should be generated correctly.'
        );
        Assert.areEqual(
            'Vendor Agreement Test PDF',
            versionRecord.VersionData.toString(),
            'Test PDF Blob should be saved as ContentVersion data.'
        );
    }

    @IsTest
    private static void createSignedAgreementPdfFromBlobShouldCreateFile() {
        Vendor_Agreement__c agreementRecord =
            buildAgreementRecord();

        Blob signedPdfBlob =
            Blob.valueOf(TEST_PDF_CONTENT);

        Test.startTest();

        Id contentDocumentId =
            VendorAgreementFileService.createSignedAgreementPdfFromBlob(
                agreementRecord,
                signedPdfBlob
            );

        Test.stopTest();

        Assert.isNotNull(
            contentDocumentId,
            'Signed ContentDocument Id should be returned.'
        );

        ContentVersion versionRecord =
            getLatestContentVersion(contentDocumentId);

        Assert.areEqual(
            VendorAgreementConstants.SIGNED_FILE_PREFIX
                + AGREEMENT_NAME,
            versionRecord.Title,
            'Signed PDF title should use signed prefix.'
        );
        Assert.areEqual(
            VendorAgreementConstants.SIGNED_FILE_PREFIX
                + AGREEMENT_NAME
                + VendorAgreementConstants.PDF_EXTENSION,
            versionRecord.PathOnClient,
            'Signed PDF path should be generated correctly.'
        );
        Assert.areEqual(
            TEST_PDF_CONTENT,
            versionRecord.VersionData.toString(),
            'Provided signed PDF Blob should be saved.'
        );
    }

    @IsTest
    private static void getLatestVersionDataShouldReturnBlob() {
        Vendor_Agreement__c agreementRecord =
            buildAgreementRecord();

        Id contentDocumentId =
            VendorAgreementFileService.createSignedAgreementPdfFromBlob(
                agreementRecord,
                Blob.valueOf(TEST_PDF_CONTENT)
            );

        Test.startTest();

        Blob versionData =
            VendorAgreementFileService.getLatestVersionData(
                String.valueOf(contentDocumentId)
            );

        Test.stopTest();

        Assert.isNotNull(
            versionData,
            'Latest VersionData should be returned.'
        );
        Assert.areEqual(
            TEST_PDF_CONTENT,
            versionData.toString(),
            'Latest VersionData should match uploaded Blob.'
        );
    }

    @IsTest
    private static void getLatestVersionDataShouldFailForBlankId() {
        Test.startTest();

        try {
            VendorAgreementFileService.getLatestVersionData('');

            Assert.fail('Blank ContentDocumentId should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void getLatestVersionDataShouldFailForMissingVersion() {
        Test.startTest();

        try {
            VendorAgreementFileService.getLatestVersionData(
                String.valueOf(UserInfo.getUserId())
            );

            Assert.fail('Missing ContentVersion should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void createSignedAgreementPdfFromBlobShouldFailForNullAgreement() {
        Test.startTest();

        try {
            VendorAgreementFileService.createSignedAgreementPdfFromBlob(
                null,
                Blob.valueOf(TEST_PDF_CONTENT)
            );

            Assert.fail('Null Vendor Agreement should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void createSignedAgreementPdfFromBlobShouldFailForAgreementWithoutId() {
        Vendor_Agreement__c agreementRecord =
            new Vendor_Agreement__c();

        Test.startTest();

        try {
            VendorAgreementFileService.createSignedAgreementPdfFromBlob(
                agreementRecord,
                Blob.valueOf(TEST_PDF_CONTENT)
            );

            Assert.fail('Vendor Agreement without Id should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void createSignedAgreementPdfFromBlobShouldFailForNullBlob() {
        Vendor_Agreement__c agreementRecord =
            buildAgreementRecord();

        Test.startTest();

        try {
            VendorAgreementFileService.createSignedAgreementPdfFromBlob(
                agreementRecord,
                null
            );

            Assert.fail('Null signed PDF Blob should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void createSignedAgreementPdfFromBlobShouldFailForEmptyBlob() {
        Vendor_Agreement__c agreementRecord =
            buildAgreementRecord();

        Test.startTest();

        try {
            VendorAgreementFileService.createSignedAgreementPdfFromBlob(
                agreementRecord,
                Blob.valueOf('')
            );

            Assert.fail('Empty signed PDF Blob should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    private static Vendor_Agreement__c buildAgreementRecord() {
        Vendor_Agreement__c agreementRecord =
            buildAgreementRecordWithReadOnlyValues();

        agreementRecord.put(
            'Vendor_Opportunity__c',
            UserInfo.getUserId()
        );

        return agreementRecord;
    }

    private static Vendor_Agreement__c buildAgreementRecordWithReadOnlyValues() {
        Map<String, Object> agreementData =
            new Map<String, Object>();

        agreementData.put(
            'attributes',
            new Map<String, Object>{
                'type' => 'Vendor_Agreement__c'
            }
        );
        agreementData.put(
            'Id',
            buildFakeVendorAgreementId()
        );
        agreementData.put(
            'Name',
            AGREEMENT_NAME
        );

        return (Vendor_Agreement__c) JSON.deserialize(
            JSON.serialize(agreementData),
            Vendor_Agreement__c.class
        );
    }

    private static String buildFakeVendorAgreementId() {
        return Vendor_Agreement__c.SObjectType
            .getDescribe()
            .getKeyPrefix()
            + '000000000001';
    }

    private static ContentVersion getLatestContentVersion(
        Id contentDocumentId
    ) {
        return [
            SELECT Id,
                   Title,
                   PathOnClient,
                   ContentDocumentId,
                   VersionData,
                   IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
    }
}