/**
 * @description Test class for MobileProjectStatusService RestResource.
 * Adheres to PMD rules and handles read-only field constraints.
 */
@isTest
private class MobileProjectStatusServiceTest {

    @testSetup
    static void setup() {
        // 1. Setup Base Data using Utility
        Contact testContact = TestDataUtility.createContact('Doe', 'john.doe@test.com', 'pass123');
        
        // Project__c lookup to Contact
        Project__c proj1 = TestDataUtility.createProject('Modern Villa', 50000, testContact.Id);
        
        // Vendor__c for the assignment
        Vendor__c vend = TestDataUtility.createVendor('Premium Steel', 'Server Room Setup', 'steel@test.com');

        // 2. Create Vendor Assignment
        // Using Method 15 from your Utility which avoids the Vendor_Opportunity__c validation logic
        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Project__c = proj1.Id,
            Vendor__c = vend.Id,
            // Vendor_Category__c is read-only (formula), so we do not write to it.
            // It will automatically pull 'Server Room Setup' from the Vendor record created above.
            Status__c = 'In-Progress',
            Completion__c = 75.5,
            Vendor_Work_Start_Date__c = System.today(),
            Vendor_Work_End_Date__c = System.today().addDays(10),
            Vendor_Tasks_Remaining_Percentage__c = 24.5
        );
        insert va;
    }

    /**
     * @description Tests successful retrieval of project and vendor data.
     */
    @isTest
    static void testGetProjectsSuccess() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectStatus';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'contactId' => con.Id
        }));

        RestContext.request = req;

        Test.startTest();
        MobileProjectStatusService.ResponseDTO response = MobileProjectStatusService.getProjects();
        Test.stopTest();

        // PMD Friendly Assertions
        Assert.isTrue(response.success, 'The service should return success: true');
        Assert.areEqual('Success', response.message, 'The message should indicate Success');
        Assert.isFalse(response.projects.isEmpty(), 'The project list should not be empty');
        
        MobileProjectStatusService.ProjectDTO pDto = response.projects[0];
        Assert.areEqual('Modern Villa', pDto.projectName, 'Project name mismatch');
        Assert.isFalse(pDto.vendors.isEmpty(), 'Vendors should be populated for the project');
    }

    /**
     * @description Tests the scenario where contactId is missing.
     */
    @isTest
    static void testGetProjectsMissingContactId() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectStatus';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"wrongKey": "noId"}');

        RestContext.request = req;

        Test.startTest();
        MobileProjectStatusService.ResponseDTO response = MobileProjectStatusService.getProjects();
        Test.stopTest();

        Assert.isFalse(response.success, 'Success should be false for missing Contact ID');
        Assert.areEqual('Missing Contact Id', response.message, 'Validation message mismatch');
    }

    /**
     * @description Tests the exception handling via malformed JSON.
     */
    @isTest
    static void testGetProjectsException() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectStatus';
        req.httpMethod = 'POST';
        // Invalid JSON structure (missing quotes/braces) to force a deserialization error
        req.requestBody = Blob.valueOf('{ contactId: "unquoted" '); 

        RestContext.request = req;

        Test.startTest();
        MobileProjectStatusService.ResponseDTO response = MobileProjectStatusService.getProjects();
        Test.stopTest();

        Assert.isFalse(response.success, 'Success should be false when an exception occurs');
        Assert.isNotNull(response.message, 'Error message should capture the exception details');
    }
}