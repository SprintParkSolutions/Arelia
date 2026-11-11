@isTest
public class TaskVendorBudgetHandlerTest {

    @testSetup
    static void setupData() {

        // Create Account and Contact using TestDataUtility.
        Account testAccount = TestDataUtility.createAccount('Budget Test Account');

        Contact testContact = TestDataUtility.createContact( 'Budget Test Contact', 'budget@test.com', 'pass123' );

        testContact.AccountId = testAccount.Id;
        update testContact;

        // Create Project using TestDataUtility.
        Project__c testProject = TestDataUtility.createProject( 'Budget Test Project', 10000, testContact.Id );

        // Create Vendor Assignment with 50% budget.
        Vendor_Assignment__c vendorAssignment =
            TestDataUtility.createVendorAssignment(testProject.Id, 50.00);

        // Initialize remaining percentage.
        vendorAssignment.Vendor_Tasks_Remaining_Percentage__c = 50.00;
        update vendorAssignment;
    }

    @isTest
    static void testValidationSuccess() {

        Vendor_Assignment__c vendorAssignment = [ SELECT Id FROM Vendor_Assignment__c LIMIT 1 ];
        // Create a valid Task using TestDataUtility.
        Task taskRecord = TestDataUtility.createTask( 'Not Started', vendorAssignment.Id, 20 );
        Test.startTest();
        // Recalculate remaining percentage.
        TaskVendorBudgetHandler.recalcRemainingFromTasks( new List<Task>{taskRecord}, null );

        Test.stopTest();

        // Expected remaining percentage = 50 - 20 = 30.
        Vendor_Assignment__c updatedAssignment = [ SELECT Vendor_Tasks_Remaining_Percentage__c FROM Vendor_Assignment__c WHERE Id = :vendorAssignment.Id ];

        System.assertEquals( 30.00, updatedAssignment.Vendor_Tasks_Remaining_Percentage__c, 'Remaining percentage should be 30% after assigning a 20% Task.' );
    }

    @isTest
    static void testValidationFailureInsert() {

        Vendor_Assignment__c vendorAssignment = [SELECT Id FROM Vendor_Assignment__c LIMIT 1 ];

        /*
         * Manual Task creation is required here.
         * TestDataUtility.createTask() inserts the Task immediately.
         * This test needs an unsaved Task so validation can be checked
         * before insertion.
         */

        Task taskRecord = new Task(
            Subject = 'Task Over Budget Limit',
            Status = 'Not Started',
            WhatId = vendorAssignment.Id,
            Assigned_Percentage__c = 60
        );
        Test.startTest();

        try {
            // Validate Task allocation before insertion.
            TaskVendorBudgetHandler.validatePercentTotals( new List<Task>{taskRecord}, null );

            // Check whether validation added an error.
            if (taskRecord.getErrors().size() > 0) {
                throw new DmlException( taskRecord.getErrors()[0].getMessage() );
            }

            insert taskRecord;

            System.assert( false, 'Task insertion should fail when assigned percentage exceeds the budget.' );

        } catch (Exception exceptionRecord) {

            System.assert( exceptionRecord.getMessage().contains('You can assign only'),  'Expected budget validation error. Actual error: ' +
                exceptionRecord.getMessage() );
        }

        Test.stopTest();
    }

    @isTest
    static void testValidationFailureUpdate() {

        Vendor_Assignment__c vendorAssignment = [ SELECT Id FROM Vendor_Assignment__c LIMIT 1 ];
        // Create a valid Task with 40% allocation using utility.
        Task taskRecord = TestDataUtility.createTask( 'Not Started', vendorAssignment.Id, 40 );
        // Recalculate remaining percentage.
        TaskVendorBudgetHandler.recalcRemainingFromTasks( new List<Task>{taskRecord}, null );
        Test.startTest();

        // Preserve the original Task values before updating.
        Task oldTaskRecord = taskRecord.clone( true, true, false, false );
        // Attempt to increase Task allocation from 40% to 60%.
        taskRecord.Assigned_Percentage__c = 60;

        try {

            // Validate the updated Task against its previous values.
            TaskVendorBudgetHandler.validatePercentTotals( new List<Task>{taskRecord}, new Map<Id, Task>{ taskRecord.Id => oldTaskRecord } );

            if (taskRecord.getErrors().size() > 0) {
                throw new DmlException( taskRecord.getErrors()[0].getMessage() );
            }

            update taskRecord;

            System.assert( false, 'Task update should fail when assigned percentage exceeds the budget.' );

        } catch (Exception exceptionRecord) {

            System.assert( exceptionRecord.getMessage().contains('You can assign only'),
                'Expected budget validation error during Task update. Actual error: ' + exceptionRecord.getMessage() );
        }

        Test.stopTest();
    }

    @isTest
    static void testRollupLogicDelete() {

        Vendor_Assignment__c vendorAssignment = [ SELECT Id FROM Vendor_Assignment__c LIMIT 1 ];

        // Create a Task with 20% allocation using utility.
        Task taskRecord = TestDataUtility.createTask( 'Not Started', vendorAssignment.Id, 20 );

        // Recalculate remaining percentage after Task creation.
        TaskVendorBudgetHandler.recalcRemainingFromTasks(
            new List<Task>{taskRecord},
            null
        );

        // Expected remaining percentage = 50 - 20 = 30.
        Vendor_Assignment__c assignmentAfterTaskInsert = [
            SELECT Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            30.00,
            assignmentAfterTaskInsert.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should be 30% after Task insertion.'
        );

        Test.startTest();

        // Delete the Task.
        delete taskRecord;

        // Recalculate remaining percentage after Task deletion.
        TaskVendorBudgetHandler.recalcRemainingFromDeleted(
            new List<Task>{taskRecord}
        );

        Test.stopTest();

        // Expected remaining percentage should return to 50%.
        Vendor_Assignment__c assignmentAfterTaskDelete = [
            SELECT Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            50.00,
            assignmentAfterTaskDelete.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should return to 50% after Task deletion.'
        );
    }

    @isTest
    static void testBulkOperations() {

        Vendor_Assignment__c vendorAssignment = [
            SELECT Id
            FROM Vendor_Assignment__c
            LIMIT 1
        ];

        /*
         * Manual Task creation is intentional here.
         * We need to insert all five Tasks in one DML operation
         * to test bulk processing.
         */

        List<Task> taskRecords = new List<Task>();

        // Create five Tasks with 10% allocation each.
        for (Integer taskIndex = 0; taskIndex < 5; taskIndex++) {

            taskRecords.add(
                new Task(
                    Subject = 'Bulk Task ' + taskIndex,
                    Status = 'Not Started',
                    WhatId = vendorAssignment.Id,
                    Assigned_Percentage__c = 10
                )
            );
        }

        Test.startTest();

        // Validate all Task allocations together.
        TaskVendorBudgetHandler.validatePercentTotals(
            taskRecords,
            null
        );

        // Insert all Tasks in a single DML operation.
        insert taskRecords;

        // Recalculate remaining percentage for the inserted Tasks.
        TaskVendorBudgetHandler.recalcRemainingFromTasks(
            taskRecords,
            null
        );

        Test.stopTest();

        Vendor_Assignment__c updatedAssignment = [
            SELECT Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        // Expected remaining percentage = 50 - (5 * 10) = 0.
        System.assertEquals(
            0.00,
            updatedAssignment.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should be 0% when the entire budget is utilized.'
        );
    }

    // =============================================
    // TEST: BUDGET INCREASE
    // =============================================

    @isTest
    static void testBudgetPercentageIncrease() {

        Vendor_Assignment__c vendorAssignment = [
            SELECT Id, Budget_Percentage__c,
                   Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            LIMIT 1
        ];

        // Create a Task with 20% allocation using utility.
        Task taskRecord = TestDataUtility.createTask(
            'Not Started',
            vendorAssignment.Id,
            20
        );

        // Verify initial remaining percentage = 50 - 20 = 30.
        Vendor_Assignment__c assignmentBeforeUpdate = [
            SELECT Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            30,
            assignmentBeforeUpdate.Vendor_Tasks_Remaining_Percentage__c,
            'Initial remaining percentage should be 30%.'
        );

        Test.startTest();

        // Increase budget from 50% to 70%.
        vendorAssignment.Budget_Percentage__c = 70;
        update vendorAssignment;

        Test.stopTest();

        Vendor_Assignment__c assignmentAfterUpdate = [
            SELECT Budget_Percentage__c,
                   Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            70,
            assignmentAfterUpdate.Budget_Percentage__c,
            'Vendor Assignment budget should be increased to 70%.'
        );

        System.assertEquals(
            50,
            assignmentAfterUpdate.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should be 50% after increasing the budget to 70%.'
        );
    }

    // =============================================
    // TEST: BUDGET DECREASE
    // =============================================

    @isTest
    static void testBudgetPercentageDecrease() {

        Vendor_Assignment__c vendorAssignment = [
            SELECT Id, Budget_Percentage__c
            FROM Vendor_Assignment__c
            LIMIT 1
        ];

        // Create a Task with 20% allocation using utility.
        Task taskRecord = TestDataUtility.createTask(
            'Not Started',
            vendorAssignment.Id,
            20
        );

        Test.startTest();

        // Decrease budget from 50% to 35%.
        vendorAssignment.Budget_Percentage__c = 35;
        update vendorAssignment;

        Test.stopTest();

        Vendor_Assignment__c assignmentAfterUpdate = [
            SELECT Budget_Percentage__c,
                   Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            35,
            assignmentAfterUpdate.Budget_Percentage__c,
            'Vendor Assignment budget should be decreased to 35%.'
        );

        System.assertEquals(
            15,
            assignmentAfterUpdate.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should be 15% after decreasing the budget to 35%.'
        );
    }

    // =============================================
    // TEST: MULTIPLE BUDGET CHANGES
    // =============================================

    @isTest
    static void testMultipleBudgetChanges() {

        Vendor_Assignment__c vendorAssignment = [
            SELECT Id, Budget_Percentage__c
            FROM Vendor_Assignment__c
            LIMIT 1
        ];

        // Create a Task with 20% allocation using utility.
        Task taskRecord = TestDataUtility.createTask(
            'Not Started',
            vendorAssignment.Id,
            20
        );

        Test.startTest();

        // First budget change: 50% to 60%.
        vendorAssignment.Budget_Percentage__c = 60;
        update vendorAssignment;

        Vendor_Assignment__c assignmentAfterFirstUpdate = [
            SELECT Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            40,
            assignmentAfterFirstUpdate.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should be 40% after the first budget change.'
        );

        // Second budget change: 60% to 40%.
        vendorAssignment.Budget_Percentage__c = 40;
        update vendorAssignment;

        Vendor_Assignment__c assignmentAfterSecondUpdate = [
            SELECT Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            20,
            assignmentAfterSecondUpdate.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should be 20% after the second budget change.'
        );

        // Third budget change: 40% to 30%.
        vendorAssignment.Budget_Percentage__c = 30;
        update vendorAssignment;

        Test.stopTest();

        Vendor_Assignment__c assignmentAfterThirdUpdate = [
            SELECT Budget_Percentage__c,
                   Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            30,
            assignmentAfterThirdUpdate.Budget_Percentage__c,
            'Vendor Assignment budget should be 30% after the third budget change.'
        );

        System.assertEquals(
            10,
            assignmentAfterThirdUpdate.Vendor_Tasks_Remaining_Percentage__c,
            'Remaining percentage should be 10% after the third budget change.'
        );
    }

    // =============================================
    // TEST: BUDGET CHANGE WITHOUT TASKS
    // =============================================

    @isTest
    static void testBudgetChangeWithoutTasks() {

        Vendor_Assignment__c vendorAssignment = [
            SELECT Id, Budget_Percentage__c
            FROM Vendor_Assignment__c
            LIMIT 1
        ];

        Test.startTest();

        // Update budget when no Tasks are assigned.
        vendorAssignment.Budget_Percentage__c = 80;
        update vendorAssignment;

        Test.stopTest();

        Vendor_Assignment__c assignmentAfterUpdate = [
            SELECT Budget_Percentage__c,
                   Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id = :vendorAssignment.Id
        ];

        System.assertEquals(
            80,
            assignmentAfterUpdate.Budget_Percentage__c,
            'Vendor Assignment budget should be updated to 80%.'
        );

        System.assertEquals(
            80,
            assignmentAfterUpdate.Vendor_Tasks_Remaining_Percentage__c,
            'When no Tasks are assigned, remaining percentage should equal the budget.'
        );
    }

    // =============================================
    // TEST: BULK BUDGET UPDATES
    // =============================================

    @isTest
    static void testBulkBudgetChanges() {

        // Retrieve the first Vendor Assignment.
        Vendor_Assignment__c firstVendorAssignment = [
            SELECT Id, Project__c, Budget_Percentage__c
            FROM Vendor_Assignment__c
            LIMIT 1
        ];

        // Create a second Vendor Assignment using utility.
        Vendor_Assignment__c secondVendorAssignment =
            TestDataUtility.createVendorAssignment(
                firstVendorAssignment.Project__c,
                60
            );

        // Create Tasks using TestDataUtility.
        Task firstTask = TestDataUtility.createTask(
            'Not Started',
            firstVendorAssignment.Id,
            10
        );

        Task secondTask = TestDataUtility.createTask(
            'Not Started',
            secondVendorAssignment.Id,
            20
        );

        // Change both Vendor Assignment budgets.
        firstVendorAssignment.Budget_Percentage__c = 70;
        secondVendorAssignment.Budget_Percentage__c = 80;

        Test.startTest();

        // Update both Vendor Assignments in one DML operation.
        update new List<Vendor_Assignment__c>{
            firstVendorAssignment,
            secondVendorAssignment
        };

        Test.stopTest();

        // Collect Vendor Assignment IDs.
        Set<Id> vendorAssignmentIds = new Set<Id>{
            firstVendorAssignment.Id,
            secondVendorAssignment.Id
        };

        // Retrieve both updated Vendor Assignments.
        Map<Id, Vendor_Assignment__c> updatedAssignments =
            new Map<Id, Vendor_Assignment__c>([
                SELECT Id,
                       Budget_Percentage__c,
                       Vendor_Tasks_Remaining_Percentage__c
                FROM Vendor_Assignment__c
                WHERE Id IN :vendorAssignmentIds
            ]);

        // First assignment: 70 - 10 = 60.
        System.assertEquals(
            60,
            updatedAssignments.get(firstVendorAssignment.Id)
                .Vendor_Tasks_Remaining_Percentage__c,
            'First Vendor Assignment should have 60% remaining.'
        );

        // Second assignment: 80 - 20 = 60.
        System.assertEquals(
            60,
            updatedAssignments.get(secondVendorAssignment.Id)
                .Vendor_Tasks_Remaining_Percentage__c,
            'Second Vendor Assignment should have 60% remaining.'
        );
    }
}