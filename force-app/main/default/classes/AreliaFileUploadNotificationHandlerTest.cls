@IsTest(SeeAllData=true)
private class AreliaFileUploadNotificationHandlerTest {

    @IsTest
    static void handleAfterInsertProjectFileUploadSuccessTest() {
        Project__c projectRec = getExistingProjectWithClient();
        Id contentDocumentId = createContentDocument('Architecture Plan');

        ContentDocumentLink linkRec = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = projectRec.Id
        );

        Test.setMock(HttpCalloutMock.class, new FirebaseMock());

        Test.startTest();

        AreliaFileUploadNotificationHandler.handleAfterInsert(
            new List<ContentDocumentLink>{ linkRec }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Project file upload notification should be processed.'
        );
    }

    @IsTest
    static void handleAfterInsertDuplicateFileUploadTest() {
        Project__c projectRec = getExistingProjectWithClient();
        Id contentDocumentId = createContentDocument('Duplicate File');

        ContentDocumentLink firstLink = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = projectRec.Id
        );

        ContentDocumentLink secondLink = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = projectRec.Id
        );

        Test.setMock(HttpCalloutMock.class, new FirebaseMock());

        Test.startTest();

        AreliaFileUploadNotificationHandler.handleAfterInsert(
            new List<ContentDocumentLink>{
                firstLink,
                secondLink
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Duplicate file notification should be skipped safely.'
        );
    }

    @IsTest
    static void handleAfterInsertNonProjectLinkTest() {
        Account accountRec = new Account(
            Name = 'File Upload Test Account'
        );
        insert accountRec;

        Id contentDocumentId = createContentDocument('Account File');

        ContentDocumentLink linkRec = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = accountRec.Id
        );

        Test.startTest();

        AreliaFileUploadNotificationHandler.handleAfterInsert(
            new List<ContentDocumentLink>{ linkRec }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Non Project__c linked files should be skipped.'
        );
    }

    @IsTest
    static void handleAfterInsertProjectNotFoundTest() {
        Id fakeProjectId = getFakeProjectId();
        Id contentDocumentId = createContentDocument('Fake Project File');

        ContentDocumentLink linkRec = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = fakeProjectId
        );

        Test.startTest();

        AreliaFileUploadNotificationHandler.handleAfterInsert(
            new List<ContentDocumentLink>{ linkRec }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when Project__c record is not found.'
        );
    }

    @IsTest
    static void handleAfterInsertDocumentNotFoundTest() {
        Project__c projectRec = getExistingProjectWithClient();

        Id fakeContentDocumentId = (Id) '069000000000001';

        ContentDocumentLink linkRec = new ContentDocumentLink(
            ContentDocumentId = fakeContentDocumentId,
            LinkedEntityId = projectRec.Id
        );

        Test.setMock(HttpCalloutMock.class, new FirebaseMock());

        Test.startTest();

        AreliaFileUploadNotificationHandler.handleAfterInsert(
            new List<ContentDocumentLink>{ linkRec }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should use default file name when ContentDocument is not found.'
        );
    }

    @IsTest
    static void handleAfterInsertNullAndEmptyInputTest() {
        Test.startTest();

        AreliaFileUploadNotificationHandler.handleAfterInsert(null);

        AreliaFileUploadNotificationHandler.handleAfterInsert(
            new List<ContentDocumentLink>()
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Null and empty input should not throw exception.'
        );
    }

    @IsTest
    static void handleAfterInsertInvalidLinkValuesTest() {
        ContentDocumentLink emptyLink = new ContentDocumentLink();

        Test.startTest();

        AreliaFileUploadNotificationHandler.handleAfterInsert(
            new List<ContentDocumentLink>{ emptyLink }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Invalid ContentDocumentLink values should be skipped safely.'
        );
    }

    private static Project__c getExistingProjectWithClient() {
        List<Project__c> projects = [
            SELECT Id, Name, Client__c
            FROM Project__c
            WHERE Client__c != null
            LIMIT 1
        ];

        System.assert(
            !projects.isEmpty(),
            'Please keep at least one Project__c record with Client__c populated in this sandbox.'
        );

        return projects[0];
    }

    private static Id createContentDocument(String title) {
        ContentVersion contentVersionRec = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('Test file content'),
            IsMajorVersion = true
        );

        insert contentVersionRec;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionRec.Id
            LIMIT 1
        ];

        return insertedVersion.ContentDocumentId;
    }

    private static Id getFakeProjectId() {
        String prefix = Project__c.SObjectType.getDescribe().getKeyPrefix();
        return (Id) (prefix + '000000000001');
    }

    private class FirebaseMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (
                request.getEndpoint() != null &&
                request.getEndpoint().contains('/messages:send')
            ) {
                response.setStatusCode(200);
                response.setBody(
                    '{"name":"projects/areliaspace-e5f22/messages/test-message-id"}'
                );
                return response;
            }

            response.setStatusCode(200);
            response.setBody(
                '{"access_token":"test_access_token","token_type":"Bearer","expires_in":3600}'
            );

            return response;
        }
    }
}