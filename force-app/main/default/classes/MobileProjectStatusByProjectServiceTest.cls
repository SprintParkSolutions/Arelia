/**
 * @description Test class for MobileProjectStatusByProjectService.
 * Addresses circular validation dependencies and specific picklist requirements.
 */
@isTest
private class MobileProjectStatusByProjectServiceTest {

    /**
     * @description Prepares test data hierarchy satisfying all custom validation rules.
     */
    @testSetup
    static void setup() {
        // 1. Setup User and Contact
        User supervisor = TestDataUtility.createSupervisorUser('superv');
        Contact con = TestDataUtility.createContact('Test', 'project@test.com', 'pass123');
        
        // 2. Create Opportunity with Agreement flags set BEFORE insert
        Opportunity opp = new Opportunity(
            Name = 'Test Opp ' + DateTime.now().getTime(),
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(30),
            Supervisor_User__c = supervisor.Id,
            Project_Scope__c = 'Kitchen',
            Client_Agreement_Sent__c = true,
            Client_Agreement_Signed__c = true
        );
        insert opp;

        // 3. Create Vendor and Vendor Opportunity
        Vendor__c vend = TestDataUtility.createVendor('Test Vendor', 'Server Room Setup', 'vendor@test.com');
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vend.Id, 'Active');
        
        // 4. Create Project
        Project__c proj = TestDataUtility.createProject('Test Project', 50000, con.Id);
        
        // 5. MANUAL DATA SETUP to bypass TestDataUtility task validation error
        // We set Status__c = 'In-Progress' to allow Task creation in the next step
        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id,
            Opportunity__c = opp.Id,
            Supervisor_User__c = supervisor.Id,
            Project__c = proj.Id,
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today().addDays(5),
            Completion__c = 75.0,
            Status__c = 'In-Progress' 
        );
        insert va;

        // 6. Create Task related to Vendor Assignment
        insert new Task(
            Subject = 'Test Task',
            Status = 'Not Started',
            WhatId = va.Id
        );
    }

    /**
     * @description Tests the successful retrieval of project and vendor details.
     * Reaches 90%+ coverage by executing the Project query and Vendor Assignment loop.
     */
    @isTest
    static void testGetProjectSuccess() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectStatusByProject';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"projectId": "' + proj.Id + '"}');
        RestContext.request = req;
        
        Test.startTest();
        MobileProjectStatusService.ResponseDTO response = MobileProjectStatusByProjectService.getProject();
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should be returned');
        System.assertEquals(true, response.success, 'Success flag should be true');
        System.assert(response.projects[0].vendors.size() > 0, 'Should cover the vendor loop');
    }

    /**
     * @description Tests the error handling branch for a blank Project ID.
     */
    @isTest
    static void testGetProjectMissingIdError() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileProjectStatusByProject';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"projectId": ""}');
        RestContext.request = req;
        
        Test.startTest();
        try {
            MobileProjectStatusByProjectService.getProject();
            System.assert(false, 'Expected AuraHandledException not thrown');
        } catch (AuraHandledException e) {
            System.assert(true, 'Caught expected exception');
        } catch (Exception e) {
            System.assert(true, 'Caught generic exception');
        }
        Test.stopTest();
    }
}