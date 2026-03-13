@isTest
public class TaskHelperTest {

    @testSetup
    static void setupData() {
        // 1. Create Prerequisites (Account & Contact) using Utility
        // Utility createProject requires a Contact ID.
        Account acc = TestDataUtility.createAccount('Task Helper Account');
        
        Contact con = TestDataUtility.createContact('Task Contact', 'task@test.com', 'pass123');
        con.AccountId = acc.Id;
        update con;

        // 2. Create Project using Utility (requires Name, Budget, ContactId)
        Project__c proj = TestDataUtility.createProject('Test Project TaskCalc', 5000, con.Id);

        // 3. Create Vendor Assignment using Utility
        // The utility sets the Project linkage automatically.
        // Using 0 as percentage since we are testing Task completion rollup, not budget.
        TestDataUtility.createVendorAssignment(proj.Id, 0);
    }

    @isTest
    static void testPartialCompletion() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // Create 2 Tasks: 1 Completed, 1 Not Started
        // Using Utility for one, standard for the other to vary status easily
        TestDataUtility.createTask('Completed', va.Id, 0);
        TestDataUtility.createTask('Not Started', va.Id, 0);

        Test.startTest();
        // Manually call the helper
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: 1 out of 2 tasks completed = 50%
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(50.00, result.Completion__c, 'Completion should be 50%');
    }

    @isTest
    static void testFullCompletion() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // Create 2 Tasks: Both Completed
        TestDataUtility.createTask('Completed', va.Id, 0);
        TestDataUtility.createTask('Completed', va.Id, 0);

        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: 2 out of 2 completed = 100%
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(100.00, result.Completion__c, 'Completion should be 100%');
    }

    @isTest
    static void testNoCompletion() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // Create 2 Tasks: None Completed
        TestDataUtility.createTask('In Progress', va.Id, 0);
        TestDataUtility.createTask('Not Started', va.Id, 0);

        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: 0 completed = 0%
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(0.00, result.Completion__c, 'Completion should be 0%');
    }

    @isTest
    static void testNoTasks() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // No tasks inserted

        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: No tasks handled gracefully (remains 0 or calculates to 0)
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        
        // Logic sets percentage = 0 if totalTasks is null/0
        System.assertEquals(0.00, result.Completion__c, 'Completion should be 0% when no tasks exist');
    }
    
    @isTest
    static void testEmptyInput() {
        // Verify guard clause (passing empty set)
        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'Should exit gracefully without errors');
    }
}