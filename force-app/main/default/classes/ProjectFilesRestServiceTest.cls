/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-06-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class ProjectFilesRestServiceTest {

    /**
     * @description High-level test to verify successful retrieval of project files.
     * Logic covers the main path of the @HttpPost method.
     */
    @isTest
    static void testGetProjectFilesSuccess() {
        // 1. Setup Data using Utility
        Contact client = TestDataUtility.createContact('Doe', 'test@example.com', 'pass123');
        Project__c proj = TestDataUtility.createProject('Test Project', 10000, client.Id);
        
        ContentVersion cv = TestDataUtility.createContentVersion('DesignDoc', 'Base64ContentGoesHere');
        TestDataUtility.linkFileToRecord(cv.Id, proj.Id);

        // 2. Mock RestContext
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/mobile/projectfiles';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'projectId' => proj.Id
        }));

        RestContext.request = req;
        RestContext.response = res;

        // 3. Execute
        Test.startTest();
        List<ProjectFilesRestService.FileDTO> results = ProjectFilesRestService.getProjectFiles();
        Test.stopTest();

        // 4. Verify
        Assert.areNotEqual(0, results.size(), 'Should return at least one file DTO');
        Assert.areEqual('DesignDoc', results[0].title, 'The file title should match the created record');
        Assert.isTrue(results[0].downloadUrl.contains(cv.Id), 'The download URL should contain the ContentVersion Id');
    }

    /**
     * @description Verifies that an empty request body returns an empty list.
     * This covers the 'raw == null' logic branches.
     */
    @isTest
    static void testGetProjectFilesEmptyBody() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(''); // Empty Body
        RestContext.request = req;

        Test.startTest();
        List<ProjectFilesRestService.FileDTO> results = ProjectFilesRestService.getProjectFiles();
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Expected empty list for empty request body');
    }

    /**
     * @description Verifies that a valid body with a missing projectId returns an empty list.
     */
    @isTest
    static void testGetProjectFilesMissingProjectId() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'otherKey' => 'noProjectId'
        }));
        RestContext.request = req;

        Test.startTest();
        List<ProjectFilesRestService.FileDTO> results = ProjectFilesRestService.getProjectFiles();
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Expected empty list when projectId is missing');
    }

    /**
     * @description Verifies that a projectId with no associated files returns an empty list.
     */
    @isTest
    static void testGetProjectFilesNoLinks() {
        Contact client = TestDataUtility.createContact('Smith', 'smith@example.com', 'pass123');
        Project__c proj = TestDataUtility.createProject('Empty Project', 5000, client.Id);

        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'projectId' => proj.Id
        }));
        RestContext.request = req;

        Test.startTest();
        List<ProjectFilesRestService.FileDTO> results = ProjectFilesRestService.getProjectFiles();
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Expected empty list for project with no files');
    }
}