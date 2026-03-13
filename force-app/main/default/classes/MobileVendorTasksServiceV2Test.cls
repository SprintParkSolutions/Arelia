/**
 * @description Test class for MobileVendorTasksServiceV2 REST API
 * PMD Rule Compliance: Assertions with messages, no SeeAllData, proper naming.
 */
@isTest
private class MobileVendorTasksServiceV2Test {

    @testSetup
    static void setupData() {
        // Create common test data using the provided utility
        Contact testContact = TestDataUtility.createContact('VendorContact', 'vendor@test.com', 'pass123');
        Project__c testProject = TestDataUtility.createProject('Test Project Alpha', 50000, testContact.Id);
        
        // Create a Vendor record
        Vendor__c testVendor = TestDataUtility.createVendor('Apex Pro Vendor', 'Server Room Setup', 'apex@pro.com');
        
        // Link Vendor to Project via Vendor Assignment
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(testProject.Id, 50.0);
        va.Vendor__c = testVendor.Id;
        update va;

        // Create Tasks related to the Vendor Assignment
        // Task 1: Status set to Completed
        TestDataUtility.createTask('Completed', va.Id, 25.0);

        // Task 2: In Progress
        TestDataUtility.createTask('In Progress', va.Id, 25.0);
    }

    @isTest
    static void testGetVendorTasksSuccess() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Vendor__c vend = [SELECT Name FROM Vendor__c LIMIT 1];

        // Prepare REST request body
        Map<String, Object> requestBodyMap = new Map<String, Object>{
            'projectId' => (String)proj.Id,
            'vendorName' => vend.Name,
            'summaryOnly' => false
        };

        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/mobileVendorTasksV2';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(requestBodyMap));
        RestContext.request = request;

        Test.startTest();
        MobileVendorTasksServiceV2.ResponseDTO response = MobileVendorTasksServiceV2.getVendorTasks();
        Test.stopTest();

        // Assertions
        Assert.isTrue(response.success, 'The API call should return a success flag of true.');
        Assert.areEqual(2, response.tasks.size(), 'The list should contain exactly 2 tasks.');
        Assert.areEqual(2, response.summary.totalTasks, 'The summary total tasks should be 2.');
        Assert.areEqual(1, response.summary.completedTasks, 'The summary completed tasks should be 1.');
        Assert.areEqual('Success', response.message, 'The response message should be "Success".');
    }

    @isTest
    static void testGetVendorTasksSummaryOnly() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Vendor__c vend = [SELECT Name FROM Vendor__c LIMIT 1];

        Map<String, Object> requestBodyMap = new Map<String, Object>{
            'projectId' => (String)proj.Id,
            'vendorName' => vend.Name,
            'summaryOnly' => true
        };

        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf(JSON.serialize(requestBodyMap));
        RestContext.request = request;

        Test.startTest();
        MobileVendorTasksServiceV2.ResponseDTO response = MobileVendorTasksServiceV2.getVendorTasks();
        Test.stopTest();

        Assert.isTrue(response.success, 'The API call should be successful even in summary-only mode.');
        Assert.areEqual(0, response.tasks.size(), 'The task list should be empty when summaryOnly is set to true.');
        Assert.areEqual(2, response.summary.totalTasks, 'The summary total count should still accurately reflect the database.');
    }

    @isTest
    static void testGetVendorTasksMissingParams() {
        // Test with empty JSON body
        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>()));
        RestContext.request = request;

        Test.startTest();
        MobileVendorTasksServiceV2.ResponseDTO response = MobileVendorTasksServiceV2.getVendorTasks();
        Test.stopTest();

        Assert.isFalse(response.success, 'The API should fail when required parameters are missing.');
        Assert.areEqual('Missing projectId or vendorName', response.message, 'The error message should specify the missing fields.');
    }

    @isTest
    static void testGetVendorTasksInvalidProject() {
        // Test with a Project ID that doesn't exist to trigger the Query Exception catch block
        Map<String, Object> requestBodyMap = new Map<String, Object>{
            'projectId' => 'a01000000000000AAA', // Fake ID format
            'vendorName' => 'NonExistent Vendor'
        };

        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf(JSON.serialize(requestBodyMap));
        RestContext.request = request;

        Test.startTest();
        MobileVendorTasksServiceV2.ResponseDTO response = MobileVendorTasksServiceV2.getVendorTasks();
        Test.stopTest();

        Assert.isFalse(response.success, 'The API should fail when no Vendor Assignment is found.');
        Assert.isNotNull(response.message, 'The response should contain an error message regarding the failure.');
    }
}