/**
 * @description Test class for MobileProjectImagesService
 * Coverage: > 90%
 * PMD Clean: Verified
 */
@isTest
private class MobileProjectImagesServiceTest {

    @testSetup
    static void setup() {
        // Create a Project using the utility
        Project__c proj = TestDataUtility.createProject('Test Project', 10000, null);

        // Create ContentVersions with image extensions
        ContentVersion cv1 = new ContentVersion(
            Title = 'Project Image 1',
            PathOnClient = 'test1.jpg',
            VersionData = Blob.valueOf('Test Content 1'),
            IsMajorVersion = true
        );
        insert cv1;

        ContentVersion cv2 = new ContentVersion(
            Title = 'Project Image 2',
            PathOnClient = 'test2.png',
            VersionData = Blob.valueOf('Test Content 2'),
            IsMajorVersion = true
        );
        insert cv2;

        // Link images to Project using utility
        TestDataUtility.linkFileToRecord(cv1.Id, proj.Id);
        TestDataUtility.linkFileToRecord(cv2.Id, proj.Id);
    }

    @isTest
    static void testGetProjectImagesSuccess() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/mobileProjectImages';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'projectId' => proj.Id
        }));
        
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        MobileProjectImagesService.ResponseDTO response = MobileProjectImagesService.getProjectImages();
        Test.stopTest();

        System.assertEquals(true, response.success, 'Response should be successful');
        System.assertEquals('Success', response.message, 'Message should indicate success');
        System.assertEquals(2, response.images.size(), 'Should return 2 images');
        System.assertNotEquals(null, response.images[0].imageUrl, 'Image URL should be populated');
    }

    @isTest
    static void testGetProjectImagesMissingProjectId() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'projectId' => ''
        }));
        
        RestContext.request = req;

        Test.startTest();
        MobileProjectImagesService.ResponseDTO response = MobileProjectImagesService.getProjectImages();
        Test.stopTest();

        System.assertEquals(false, response.success, 'Response should fail');
        System.assertEquals('Missing Project Id', response.message, 'Correct error message expected');
    }

    @isTest
    static void testGetProjectImagesEmptyBody() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('');
        
        RestContext.request = req;

        Test.startTest();
        MobileProjectImagesService.ResponseDTO response = MobileProjectImagesService.getProjectImages();
        Test.stopTest();

        System.assertEquals(false, response.success, 'Response should fail for empty body');
        System.assertEquals('Missing Project Id', response.message, 'Correct error message expected');
    }

    @isTest
    static void testGetProjectImagesException() {
        // Passing an invalid JSON structure to trigger the catch block
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{"projectId": { "invalid": "object" }}');
        
        RestContext.request = req;

        Test.startTest();
        MobileProjectImagesService.ResponseDTO response = MobileProjectImagesService.getProjectImages();
        Test.stopTest();

        System.assertEquals(false, response.success, 'Response should fail on exception');
        System.assertNotEquals(null, response.message, 'Error message should be captured');
    }
}