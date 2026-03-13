/**
 * @description Updated Test class for MobileDashboardService.
 * Fixes CreatedDate collision and AuraHandledException message assertion.
 */
@isTest
private class MobileDashboardServiceTest {

    @testSetup
    static void setupData() {
        // Create a test contact
        Contact testContact = TestDataUtility.createContact('Doe', 'john.doe@test.com', 'Pass123!');
        
        // Create projects. 
        // Note: In tests, they may have the same CreatedDate.
        TestDataUtility.createProject('Project Alpha', 50000, testContact.Id);
        TestDataUtility.createProject('Project Beta', 75000, testContact.Id);
    }

    /**
     * @description PMD: Validate that exception is thrown when ContactId is missing.
     */
    @isTest
    static void testGetDashboardMissingContactId() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/dashboard';
        req.httpMethod = 'GET';
        RestContext.request = req;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            MobileDashboardService.getDashboard();
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'An AuraHandledException should have been thrown');
    }

    @isTest
    static void testGetDashboardWithProjectId() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Project__c proj = [SELECT Id, Name FROM Project__c WHERE Name = 'Project Alpha' LIMIT 1];

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/dashboard';
        req.httpMethod = 'GET';
        req.addParameter('contactId', con.Id);
        req.addParameter('projectId', proj.Id);
        RestContext.request = req;

        Test.startTest();
        MobileDashboardService.DashboardResponse response = MobileDashboardService.getDashboard();
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response object should exist');
        Assert.areEqual(proj.Name, response.projectName, 'Should match the specific project ID provided');
    }

    @isTest
    static void testGetDashboardBackwardCompatibility() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        // To fix the ordering issue, we manually set the CreatedDate of one project 
        // to be clearly in the past.
        Project__c oldProj = [SELECT Id FROM Project__c WHERE Name = 'Project Alpha' LIMIT 1];
        Test.setCreatedDate(oldProj.Id, DateTime.now().addDays(-1));

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/dashboard';
        req.httpMethod = 'GET';
        req.addParameter('contactId', con.Id);
        RestContext.request = req;

        Test.startTest();
        MobileDashboardService.DashboardResponse response = MobileDashboardService.getDashboard();
        Test.stopTest();

        // Now 'Project Beta' is definitively the newest.
        Assert.areEqual('Project Beta', response.projectName, 'Should return the most recently created project');
    }

    @isTest
    static void testGetDashboardNoProjects() {
        Contact emptyCon = TestDataUtility.createContact('NoProj', 'none@test.com', 'Pass123!');

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/dashboard';
        req.httpMethod = 'GET';
        req.addParameter('contactId', emptyCon.Id);
        RestContext.request = req;

        Test.startTest();
        MobileDashboardService.DashboardResponse response = MobileDashboardService.getDashboard();
        Test.stopTest();

        Assert.areEqual('No Active Project', response.projectName, 'Should handle contact with no projects');
        Assert.areEqual(0, response.budget, 'Budget should be zero');
    }
}