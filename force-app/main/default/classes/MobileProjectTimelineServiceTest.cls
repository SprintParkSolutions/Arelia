/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-05-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class MobileProjectTimelineServiceTest {

    /**
     * @description Test setup to prepare common data using the provided Utility class.
     */
    @testSetup
    static void setupData() {
        // Create a test contact to act as the client
        Contact testContact = TestDataUtility.createContact('Doe', 'john.doe@test.com', 'password123');
        
        // Create multiple projects associated with this contact
        TestDataUtility.createProject('Project Alpha', 10000.00, testContact.Id);
        TestDataUtility.createProject('Project Beta', 25000.00, testContact.Id);
    }

    /**
     * @description Verifies that the service returns the correct timelines for a valid Contact ID.
     */
    @isTest
    static void testGetProjectTimelineSuccess() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/mobileProjectTimeline';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"contactId": "' + con.Id + '"}');
        
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        MobileProjectTimelineService.ResponseDTO response = MobileProjectTimelineService.getProjectTimeline();
        Test.stopTest();

        Assert.isTrue(response.success, 'The response should indicate success.');
        Assert.areEqual('Success', response.message, 'The message should be Success.');
        Assert.areEqual(2, response.timelines.size(), 'Should have returned 2 projects.');
        Assert.areEqual('Project Alpha', response.timelines[0].projectName, 'Project names should match.');
    }

    /**
     * @description Verifies the error handling when the contactId is missing from the request.
     */
    @isTest
    static void testGetProjectTimelineMissingId() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectTimeline';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"wrongKey": "someValue"}');
        
        RestContext.request = req;

        Test.startTest();
        MobileProjectTimelineService.ResponseDTO response = MobileProjectTimelineService.getProjectTimeline();
        Test.stopTest();

        Assert.isFalse(response.success, 'The response should indicate failure.');
        Assert.areEqual('Missing Contact Id', response.message, 'Error message should match.');
        Assert.isTrue(response.timelines.isEmpty(), 'Timeline list should be empty.');
    }

    /**
     * @description Verifies behavior when the request body is null or empty.
     */
    @isTest
    static void testGetProjectTimelineEmptyBody() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectTimeline';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(''); // Empty string
        
        RestContext.request = req;

        Test.startTest();
        MobileProjectTimelineService.ResponseDTO response = MobileProjectTimelineService.getProjectTimeline();
        Test.stopTest();

        Assert.isFalse(response.success, 'Should fail because of missing contactId.');
        Assert.areEqual('Missing Contact Id', response.message, 'Error message should match.');
    }

    /**
     * @description Verifies the catch block by providing malformed JSON.
     */
    @isTest
    static void testGetProjectTimelineException() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectTimeline';
        req.httpMethod = 'POST';
        // Malformed JSON (missing closing brace) to trigger deserialization exception
        req.requestBody = Blob.valueOf('{"contactId": "invalidId" '); 
        
        RestContext.request = req;

        Test.startTest();
        MobileProjectTimelineService.ResponseDTO response = MobileProjectTimelineService.getProjectTimeline();
        Test.stopTest();

        Assert.isFalse(response.success, 'The response should indicate failure.');
        Assert.isNotNull(response.message, 'The exception message should be captured.');
    }
}