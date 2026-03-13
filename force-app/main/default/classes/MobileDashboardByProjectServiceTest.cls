/**
 * @description Test class for MobileDashboardByProjectService
 * Adheres to PMD rules and ensures high code coverage.
 */
@isTest
private class MobileDashboardByProjectServiceTest {

    /**
     * @description Test setup to prepare common data
     */
    @testSetup
    static void setup() {
        // Create a contact for project requirements
        Contact con = TestDataUtility.createContact('Doe', 'john.doe@test.com', 'Pass123');
        
        // Create a project using the utility
        TestDataUtility.createProject('Test Project Alpha', 50000.00, con.Id);
    }

    /**
     * @description Tests the successful retrieval of dashboard data
     */
    @isTest
    static void testGetDashboardSuccess() {
        // Retrieve the project created in setup
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // Prepare REST Context
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/mobile/dashboard-by-project';
        req.httpMethod = 'POST';
        
        // Prepare JSON input body
        Map<String, String> bodyMap = new Map<String, String>();
        bodyMap.put('projectId', proj.Id);
        req.requestBody = Blob.valueOf(JSON.serialize(bodyMap));

        RestContext.request = req;
        RestContext.response = res;

        // Execute service
        Test.startTest();
        MobileDashboardByProjectService.DashboardResponse response = MobileDashboardByProjectService.getDashboard();
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals('Test Project Alpha', response.projectName, 'Project name mismatch');
        System.assertEquals(50000.00, response.budget, 'Budget mismatch');
    }

    /**
     * @description Tests the service when an empty or null ProjectId is provided
     */
    @isTest
    static void testGetDashboardMissingId() {
        // Prepare REST Context with empty projectId
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/dashboard-by-project';
        req.httpMethod = 'POST';
        
        Map<String, String> bodyMap = new Map<String, String>();
        bodyMap.put('projectId', '');
        req.requestBody = Blob.valueOf(JSON.serialize(bodyMap));

        RestContext.request = req;

        // Execute service and catch expected exception
        Test.startTest();
        try {
            MobileDashboardByProjectService.getDashboard();
            System.assert(false, 'Should have thrown an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception'), 'Exception message should be logged');
        }
        Test.stopTest();
    }

    /**
     * @description Tests the service when an invalid ProjectId format is provided
     */
    @isTest
    static void testGetDashboardInvalidId() {
        // Prepare REST Context with invalid ID format
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/dashboard-by-project';
        req.httpMethod = 'POST';
        
        Map<String, String> bodyMap = new Map<String, String>();
        // Using a non-existent but validly formatted ID suffix or random string
        bodyMap.put('projectId', 'a01000000000000AAA'); 
        req.requestBody = Blob.valueOf(JSON.serialize(bodyMap));

        RestContext.request = req;

        // Execute service and catch Query Exception
        Test.startTest();
        try {
            MobileDashboardByProjectService.getDashboard();
            System.assert(false, 'Should have thrown a QueryException for no rows found');
        } catch (System.QueryException e) {
            System.assertNotEquals(null, e.getMessage(), 'QueryException expected for missing record');
        }
        Test.stopTest();
    }
}