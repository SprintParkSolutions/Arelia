/**
 * @description Corrected Test class for MobileProjectTimelineByProjectService
 * Addresses "Field is not writeable" errors by removing direct assignments to formula fields.
 */
@isTest
private class MobileProjectTimelineByProjectSvcTest {

    @testSetup
    static void setupData() {
        // Create a Contact for the Project
        Contact con = TestDataUtility.createContact('Doe', 'john@example.com', 'pass123');
        
        // Create a Project using the Utility Class
        // We only assign writeable fields here.
        Project__c proj = TestDataUtility.createProject('Test Project Timeline', 50000, con.Id);
        
        // Update writeable fields only. 
        // Formula fields like Estimated_End_Date__c will calculate based on these if configured.
        proj.Start_Date__c = Date.today();
        proj.Status__c = 'In Progress';
        // proj.Estimated_Project_Duration__c = '6 Months'; // Uncomment if this is a picklist/text, not a formula
        
        update proj;
    }

    @isTest
    static void testGetTimelineSuccess() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/mobileProjectTimelineByProject';
        req.httpMethod = 'POST';
        Map<String, String> bodyMap = new Map<String, String>{
            'projectId' => proj.Id
        };
        req.requestBody = Blob.valueOf(JSON.serialize(bodyMap));
        
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        MobileProjectTimelineByProjectService.TimelineResponse response = 
            MobileProjectTimelineByProjectService.getTimeline();
        Test.stopTest();

        System.assert(response.success, 'The service should return success for a valid project ID.');
        System.assertEquals('Success', response.message, 'Message should be Success');
        System.assertNotEquals(0, response.timelines.size(), 'Timeline list should not be empty');
    }

    @isTest
    static void testGetTimelineMissingProjectId() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{'projectId' => ''}));
        RestContext.request = req;

        Test.startTest();
        MobileProjectTimelineByProjectService.TimelineResponse response = 
            MobileProjectTimelineByProjectService.getTimeline();
        Test.stopTest();

        System.assertEquals(false, response.success, 'Success should be false');
        System.assertEquals('ProjectId is required', response.message, 'Error message mismatch');
    }

    @isTest
    static void testGetTimelineProjectNotFound() {
        // Create a valid Id format that doesn't exist in the DB
        String fakeId = Project__c.SObjectType.getDescribe().getKeyPrefix() + '000000000AAA';
        
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{'projectId' => fakeId}));
        RestContext.request = req;

        Test.startTest();
        MobileProjectTimelineByProjectService.TimelineResponse response = 
            MobileProjectTimelineByProjectService.getTimeline();
        Test.stopTest();

        System.assertEquals(false, response.success, 'Success should be false');
        System.assertEquals('Project not found', response.message, 'Error message mismatch');
    }

    @isTest
    static void testGetTimelineEmptyBody() {
        RestRequest req = new RestRequest();
        req.requestBody = null;
        RestContext.request = req;

        Test.startTest();
        MobileProjectTimelineByProjectService.TimelineResponse response = 
            MobileProjectTimelineByProjectService.getTimeline();
        Test.stopTest();

        System.assertEquals(false, response.success, 'Success should be false');
        System.assertEquals('Request body is empty', response.message, 'Error message mismatch');
    }

    @isTest
    static void testGetTimelineException() {
        // Triggering a JSON Deserialization exception with malformed JSON
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{ "projectId": '); 
        RestContext.request = req;

        Test.startTest();
        MobileProjectTimelineByProjectService.TimelineResponse response = 
            MobileProjectTimelineByProjectService.getTimeline();
        Test.stopTest();

        System.assertEquals(false, response.success, 'Exception should result in success = false');
        System.assert(response.message != null, 'Message should contain exception details');
    }
}