/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementFileServiceTest
 * Author          : <YourName>
 * Created Date    : Jun 29, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 29, 2026
 * Description     : Test class for ClientAgreementFileService.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class ClientAgreementFileServiceTest {

    private static final String PDF_FILE_NAME = 'Client_Agreement_Test.pdf';
    private static final String PDF_BODY = '%PDF-1.4 Test PDF Content';

    @IsTest
    static void savePdfFileShouldCreateContentVersionFromBase64() {
        Account linkedRecord = createAccount('PDF Parent Record');

        String pdfBase64 = EncodingUtil.base64Encode(Blob.valueOf(PDF_BODY));

        Test.startTest();
        Id contentVersionId = ClientAgreementFileService.savePdfFile(
            PDF_FILE_NAME,
            pdfBase64,
            linkedRecord.Id
        );
        Test.stopTest();

        ContentVersion insertedVersion = getContentVersion(contentVersionId);

        System.assertNotEquals(null, contentVersionId, 'ContentVersion Id should be returned.');
        System.assertEquals('Client_Agreement_Test', insertedVersion.Title);
        System.assertEquals(PDF_FILE_NAME, insertedVersion.PathOnClient);
        System.assertNotEquals(null, insertedVersion.ContentDocumentId);

        assertFileLinkedToRecord(
            insertedVersion.ContentDocumentId,
            linkedRecord.Id
        );
    }

    @IsTest
    static void savePdfFileShouldCreateContentVersionFromDataUriBase64() {
        Account linkedRecord = createAccount('Data URI PDF Parent Record');

        String pdfBase64 =
            'data:application/pdf;base64,' +
            EncodingUtil.base64Encode(Blob.valueOf(PDF_BODY));

        Test.startTest();
        Id contentVersionId = ClientAgreementFileService.savePdfFile(
            PDF_FILE_NAME,
            pdfBase64,
            linkedRecord.Id
        );
        Test.stopTest();

        ContentVersion insertedVersion = getContentVersion(contentVersionId);

        System.assertNotEquals(null, contentVersionId, 'ContentVersion Id should be returned.');
        System.assertEquals('Client_Agreement_Test', insertedVersion.Title);
        System.assertEquals(PDF_FILE_NAME, insertedVersion.PathOnClient);

        assertFileLinkedToRecord(
            insertedVersion.ContentDocumentId,
            linkedRecord.Id
        );
    }

    @IsTest
    static void savePdfFileFromBlobShouldCreateContentVersion() {
        Account linkedRecord = createAccount('Blob PDF Parent Record');

        Test.startTest();
        Id contentVersionId = ClientAgreementFileService.savePdfFileFromBlob(
            PDF_FILE_NAME,
            Blob.valueOf(PDF_BODY),
            linkedRecord.Id
        );
        Test.stopTest();

        ContentVersion insertedVersion = getContentVersion(contentVersionId);

        System.assertNotEquals(null, contentVersionId, 'ContentVersion Id should be returned.');
        System.assertEquals('Client_Agreement_Test', insertedVersion.Title);
        System.assertEquals(PDF_FILE_NAME, insertedVersion.PathOnClient);
        System.assertNotEquals(null, insertedVersion.ContentDocumentId);

        assertFileLinkedToRecord(
            insertedVersion.ContentDocumentId,
            linkedRecord.Id
        );
    }

    @IsTest
    static void savePdfFileFromBlobShouldHandleFileNameWithoutPdfExtension() {
        Account linkedRecord = createAccount('No Extension Parent Record');

        Test.startTest();
        Id contentVersionId = ClientAgreementFileService.savePdfFileFromBlob(
            'AgreementFile',
            Blob.valueOf(PDF_BODY),
            linkedRecord.Id
        );
        Test.stopTest();

        ContentVersion insertedVersion = getContentVersion(contentVersionId);

        System.assertEquals('AgreementFile', insertedVersion.Title);
        System.assertEquals('AgreementFile', insertedVersion.PathOnClient);
    }

    @IsTest
    static void savePdfFileShouldThrowWhenFileNameIsBlank() {
        Account linkedRecord = createAccount('Blank File Name Parent');

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementFileService.savePdfFile(
                '',
                EncodingUtil.base64Encode(Blob.valueOf(PDF_BODY)),
                linkedRecord.Id
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(null, exceptionRecord, 'Exception should be available.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Blank file name should throw exception.');
    }

    @IsTest
    static void savePdfFileShouldThrowWhenBase64IsBlank() {
        Account linkedRecord = createAccount('Blank Base64 Parent');

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementFileService.savePdfFile(
                PDF_FILE_NAME,
                '',
                linkedRecord.Id
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(null, exceptionRecord, 'Exception should be available.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Blank PDF content should throw exception.');
    }

    @IsTest
    static void savePdfFileShouldThrowWhenBase64IsInvalid() {
        Account linkedRecord = createAccount('Invalid Base64 Parent');

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementFileService.savePdfFile(
                PDF_FILE_NAME,
                'invalid-base64-content',
                linkedRecord.Id
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(null, exceptionRecord, 'Exception should be available.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Invalid Base64 should throw exception.');
    }

    @IsTest
    static void savePdfFileFromBlobShouldThrowWhenFileNameIsBlank() {
        Account linkedRecord = createAccount('Blank Blob File Name Parent');

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementFileService.savePdfFileFromBlob(
                null,
                Blob.valueOf(PDF_BODY),
                linkedRecord.Id
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(null, exceptionRecord, 'Exception should be available.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Blank file name should throw exception.');
    }

    @IsTest
    static void savePdfFileFromBlobShouldThrowWhenBlobIsNull() {
        Account linkedRecord = createAccount('Null Blob Parent');

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementFileService.savePdfFileFromBlob(
                PDF_FILE_NAME,
                null,
                linkedRecord.Id
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(null, exceptionRecord, 'Exception should be available.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Null PDF blob should throw exception.');
    }

    @IsTest
    static void savePdfFileFromBlobShouldThrowWhenLinkedEntityIdIsNull() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementFileService.savePdfFileFromBlob(
                PDF_FILE_NAME,
                Blob.valueOf(PDF_BODY),
                null
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(null, exceptionRecord, 'Exception should be available.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Null linked record Id should throw exception.');
    }

    private static Account createAccount(String accountName) {
        Account accountRecord = new Account();
        accountRecord.Name = accountName;
        insert accountRecord;
        return accountRecord;
    }

    private static ContentVersion getContentVersion(Id contentVersionId) {
        return [
            SELECT Id,
                   Title,
                   PathOnClient,
                   ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
    }

    private static void assertFileLinkedToRecord(
        Id contentDocumentId,
        Id linkedEntityId
    ) {
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :linkedEntityId
        ];

        System.assertEquals(
            1,
            links.size(),
            'ContentDocumentLink should be created through FirstPublishLocationId.'
        );
    }
}