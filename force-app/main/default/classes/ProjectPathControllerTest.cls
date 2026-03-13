@isTest
public class ProjectPathControllerTest {

    @testSetup
    static void setupData() {
        // 1. Create Prerequisites (Account & Contact) using Utility
        Account acc = TestDataUtility.createAccount('Test Project Account');
        
        Contact con = TestDataUtility.createContact('Test Contact', 'test@project.com', 'password123');
        con.AccountId = acc.Id;
        update con;

        // 2. Create Project using Utility (requires Name, Budget, ContactId)
        TestDataUtility.createProject('Test Project Path', 10000, con.Id);
    }

    @isTest
    static void testProjectInitiated() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        proj.Status__c = 'Initiated';
        update proj;

        Test.startTest();
        String stage = ProjectPathController.getCurrentStage(proj.Id);
        Test.stopTest();

        Assert.areEqual('Project Initiated', stage, 'Should return Initiated for new projects');
    }

    @isTest
    static void testAssignVendorAssignments() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        proj.Status__c = 'In Progress';
        update proj;

        // Ensure no assignments exist
        delete [SELECT Id FROM Vendor_Assignment__c WHERE Project__c = :proj.Id];

        Test.startTest();
        String stage = ProjectPathController.getCurrentStage(proj.Id);
        Test.stopTest();

        Assert.areEqual('Assign Vendor Assignments', stage, 'Should ask for assignments if In Progress but none exist');
    }

    @isTest
    static void testProjectOngoing() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        proj.Status__c = 'In Progress';
        update proj;

        // Use Utility to create Vendor Assignment (requires ProjectId, BudgetPercentage)
        TestDataUtility.createVendorAssignment(proj.Id, 50.0);

        Test.startTest();
        String stage = ProjectPathController.getCurrentStage(proj.Id);
        Test.stopTest();

        Assert.areEqual('Project Ongoing', stage, 'Should be Ongoing if In Progress + Vendors exist');
    }

    @isTest
    static void testHold() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        proj.Status__c = 'Hold';
        // FIX: Satisfy Validation Rule: Hold Reason is required
        proj.Hold_Reason__c = 'Vendor Abscond'; 
        update proj;

        Test.startTest();
        String stage = ProjectPathController.getCurrentStage(proj.Id);
        Test.stopTest();

        Assert.areEqual('Hold', stage, 'Should match Hold status');
    }

    @isTest
    static void testCompleted() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        proj.Status__c = 'Completed';
        // FIX: Satisfy Validation Rule: Completion Status must be 100%
        proj.Project_Completion_Status__c = 100;
        update proj;

        Test.startTest();
        String stage = ProjectPathController.getCurrentStage(proj.Id);
        Test.stopTest();

        Assert.areEqual('Project Completion', stage, 'Should match Completed status');
    }

    @isTest
    static void testNullInput() {
        Test.startTest();
        String stage = ProjectPathController.getCurrentStage(null);
        Test.stopTest();

        Assert.isNull(stage, 'Should return null for null input');
    }

    @isTest
    static void testInvalidId() {
        // Create a fake ID for Project__c
        String fakeId = String.valueOf(Project__c.SObjectType.getDescribe().getKeyPrefix()) + '000000000000';
        
        Test.startTest();
        String stage = ProjectPathController.getCurrentStage((Id)fakeId);
        Test.stopTest();

        Assert.isNull(stage, 'Should return null if record not found');
    }
}