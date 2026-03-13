@isTest
public class TaskBulkControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User
        User u = TestDataUtility.createSupervisorUser('tasktest');

        // 2. Create Opportunity (to link tasks to)
        TestDataUtility.createOpportunity('Task Bulk Opp', u.Id);
    }

    // ==========================================
    // CREATE TESTS
    // ==========================================

    @isTest
    static void testCreateTasksSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Prepare a list of tasks in memory
        List<Task> tasksToInsert = new List<Task>();
        
        for(Integer i=0; i<5; i++) {
            Task t = new Task(
                Subject = 'Test Task ' + i,
                Status = 'Not Started',
                Priority = 'Normal',
                WhatId = opp.Id,
                ActivityDate = Date.today().addDays(i)
            );
            tasksToInsert.add(t);
        }

        Test.startTest();
        List<Task> results = TaskBulkController.createTasks(tasksToInsert);
        Test.stopTest();

        // Verify insertion
        Assert.areEqual(5, results.size(), 'Return list size should match');
        List<Task> insertedTasks = [SELECT Id FROM Task WHERE WhatId = :opp.Id];
        Assert.areEqual(5, insertedTasks.size(), 'Should have inserted 5 tasks in DB');
    }

    @isTest
    static void testCreateTasksEmptyList() {
        Test.startTest();
        // Passing empty list should do nothing and not throw errors
        List<Task> result = TaskBulkController.createTasks(new List<Task>());
        Test.stopTest();
        
        // FIX: Added assertion message (ApexAssertionsShouldIncludeMessage)
        Assert.areEqual(0, result.size(), 'Should return empty list for empty input');
    }

    @isTest
    static void testCreateTasksException() {
        Test.startTest();
        try {
            // Passing NULL causes NullPointerException in controller
            TaskBulkController.createTasks(null);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught and handled');
        }
        Test.stopTest();
    }

    // ==========================================
    // UPDATE TESTS
    // ==========================================

    @isTest
    static void testUpdateTasksSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // 1. Create Task using Utility
        Task t = TestDataUtility.createTask('Not Started', opp.Id, 0);
        
        // 2. Modify it
        t.Status = 'Completed';
        
        Test.startTest();
        TaskBulkController.updateTasks(new List<Task>{t});
        Test.stopTest();
        
        // 3. Verify
        Task updatedT = [SELECT Status FROM Task WHERE Id = :t.Id];
        Assert.areEqual('Completed', updatedT.Status, 'Task status should be updated');
    }

    @isTest
    static void testUpdateTasksException() {
        Test.startTest();
        try {
            // Passing NULL causes exception
            TaskBulkController.updateTasks(null);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }

    // ==========================================
    // READ / QUERY TESTS
    // ==========================================

    @isTest
    static void testHasExistingTasks() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // 1. Initial State: False
        Boolean initial = TaskBulkController.hasExistingTasks(opp.Id);
        Assert.isFalse(initial, 'Should be false initially');

        // 2. Create Data
        TestDataUtility.createTask('In Progress', opp.Id, 2);

        // 3. Final State: True
        Boolean finalState = TaskBulkController.hasExistingTasks(opp.Id);
        Assert.isTrue(finalState, 'Should be true after creation');
    }

    @isTest
    static void testGetExistingTasks() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        TestDataUtility.createTask('Deferred', opp.Id, 5);

        Test.startTest();
        List<Task> tasks = TaskBulkController.getExistingTasks(opp.Id);
        Test.stopTest();

        Assert.areEqual(1, tasks.size(), 'Should return created task');
        Assert.areEqual('Deferred', tasks[0].Status, 'Should return correct status');
    }

    // ==========================================
    // FILE HANDLING TESTS
    // ==========================================

    @isTest
    static void testGetTaskFiles() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // 1. Create Task
        Task t = TestDataUtility.createTask('Waiting', opp.Id, 0);

        // 2. Create Files using Utility
        ContentVersion cv1 = TestDataUtility.createContentVersion('File One', 'Data1');
        ContentVersion cv2 = TestDataUtility.createContentVersion('File Two', 'Data2');

        // 3. Link Files to Task using Utility
        TestDataUtility.linkFileToRecord(cv1.Id, t.Id);
        TestDataUtility.linkFileToRecord(cv2.Id, t.Id);

        Test.startTest();
        // 4. Call Controller
        Map<Id, List<TaskBulkController.FileData>> result = TaskBulkController.getTaskFiles(new List<Id>{t.Id});
        Test.stopTest();

        // 5. Verification
        Assert.isTrue(result.containsKey(t.Id), 'Map should contain Task ID');
        
        List<TaskBulkController.FileData> files = result.get(t.Id);
        Assert.areEqual(2, files.size(), 'Should return 2 files for this task');
        
        // Verify Wrapper contents
        Set<String> titles = new Set<String>();
        for(TaskBulkController.FileData fd : files) {
            titles.add(fd.fileName);
        }
        
        Boolean foundFile1 = false; 
        for(String name : titles) { 
            // FIX: Added braces for IfStmtsMustUseBraces rule
            if(name.contains('File One')) {
                foundFile1 = true; 
            }
        }
        Assert.isTrue(foundFile1, 'File One should be in the list');
    }
}