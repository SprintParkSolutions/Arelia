@IsTest(SeeAllData=false)
private class MobileProjectFilesServiceTest {

    @isTest
    static void testGetProjectFilesReturnsMissingProjectIdForBlankInput() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/project-files';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'projectId' => ''
        }));

        RestContext.request = req;

        MobileProjectFilesService.ResponseDTO response = MobileProjectFilesService.getProjectFiles();

        System.assertEquals(false, response.success);
        System.assertEquals('Missing Project Id', response.message);
        System.assertEquals(0, response.totalCount);
        System.assertEquals(0, response.files.size());
    }

    @isTest
    static void testGetProjectFilesReturnsNoFilesWhenNoContentLinked() {
        Contact testContact = TestDataUtility.createContact(
            'FileContact',
            'filecontact' + DateTime.now().getTime() + '@example.com',
            'Password123!'
        );
        Project__c project = TestDataUtility.createProject('Project Without Files', 50000, testContact.Id);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/project-files';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'projectId' => project.Id
        }));

        RestContext.request = req;

        MobileProjectFilesService.ResponseDTO response = MobileProjectFilesService.getProjectFiles();

        System.assertEquals(true, response.success);
        System.assertEquals('No files found for this project.', response.message);
        System.assertEquals(0, response.totalCount);
        System.assertEquals(0, response.files.size());
    }

    @isTest
    static void testGetProjectFilesReturnsFileDtoForLinkedContent() {
        Contact testContact = TestDataUtility.createContact(
            'FileContact2',
            'filecontact2' + DateTime.now().getTime() + '@example.com',
            'Password123!'
        );
        Project__c project = TestDataUtility.createProject('Project With Files', 90000, testContact.Id);

        ContentVersion cv = TestDataUtility.createContentVersion('Project File Document', 'PDF content bytes');
        TestDataUtility.linkFileToRecord(cv.Id, project.Id);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/project-files';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'projectId' => project.Id
        }));

        RestContext.request = req;

        MobileProjectFilesService.ResponseDTO response = MobileProjectFilesService.getProjectFiles();

        System.assertEquals(true, response.success);
        System.assertEquals('Success', response.message);
        System.assertEquals(1, response.totalCount);
        System.assertEquals(1, response.files.size());

        ContentDocumentLink link = [
            SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileType,
                   ContentDocument.ContentSize, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :project.Id
            LIMIT 1
        ];

        MobileProjectFilesService.FileDTO fileDto = response.files[0];
        System.assertEquals(link.ContentDocumentId, fileDto.documentId);
        System.assertEquals(link.ContentDocument.LatestPublishedVersionId, fileDto.versionId);
        System.assertEquals(link.ContentDocument.Title, fileDto.title);
        System.assertEquals(link.ContentDocument.FileType, fileDto.fileType);
        System.assertEquals(Integer.valueOf(link.ContentDocument.ContentSize), fileDto.fileSize);
        System.assertEquals('/sfc/servlet.shepherd/version/download/' + link.ContentDocument.LatestPublishedVersionId, fileDto.downloadUrl);
        System.assertEquals(
            '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY512&versionId=' + link.ContentDocument.LatestPublishedVersionId,
            fileDto.previewUrl
        );
    }
}