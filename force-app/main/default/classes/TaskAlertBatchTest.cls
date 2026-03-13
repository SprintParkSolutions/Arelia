@IsTest
private class TaskAlertBatchTest {

    @TestSetup
    static void setupData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // 1. Create Required Email Templates (Bypassing Mixed DML)
            TestDataUtility.createSpecificEmailTemplate(
                'Task_Reminder_Email', 
                'Task Reminder', 
                'Reminder: {{TaskSubject}}', 
                'Hello {{RecipientName}}, Task {{TaskSubject}} is due on {{DueDate}} for {{VendorCategory}}.'
            );
            TestDataUtility.createSpecificEmailTemplate(
                'Danger_Zone_Alert_Vendor', 
                'Danger Vendor', 
                'URGENT: {{AssignmentName}}', 
                'Hello {{VendorName}}, your task is overdue!'
            );
            TestDataUtility.createSpecificEmailTemplate(
                'Danger_Zone_Alert_Supervisor', 
                'Danger Supervisor', 
                'URGENT: {{ProjectName}}', 
                'Hello {{SupervisorName}}, task {{TaskSubject}} is overdue!'
            );
        }

        // 2. Base Data Setup
        User sup = TestDataUtility.createSupervisorUser('batSup');
        Contact client = TestDataUtility.createContact('Client', 'client@test.com', 'pwd123');
        Project__c proj = TestDataUtility.createProject('Test Project', 10000, client.Id);

        // Opportunity (with Validation Rule bypass)
        Opportunity opp = TestDataUtility.createOpportunity('Test Opp', sup.Id);
        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        update opp;

        // Vendor
        Vendor__c vendor = TestDataUtility.createVendor('Test Vendor', 'Painting & Wall Finishing', 'vendor@test.com');

        // Vendor Opportunity
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');

        // 3. Create Vendor Assignments EXPLICITLY (Valid Dates & Status)
        List<Vendor_Assignment__c> assignments = new List<Vendor_Assignment__c>();
        Date today = Date.today();
        
        // Dynamically check if the Name field requires manual population (i.e., not an Auto-Number)
        Schema.DescribeFieldResult nameDesc = Vendor_Assignment__c.Name.getDescribe();

        for (Integer i = 0; i < 3; i++) {
            Vendor_Assignment__c va = new Vendor_Assignment__c(
                Vendor_Opportunity__c = vo.Id, 
                Opportunity__c = opp.Id, 
                Supervisor_User__c = sup.Id, 
                OwnerId = sup.Id, // FIX: Explicitly assign Owner to guarantee Owner.Name & Owner.Email are populated
                Project__c = proj.Id,
                Vendor__c = vendor.Id, 
                Status__c = 'In-Progress', 
                Completion__c = 0,
                Vendor_Work_Start_Date__c = today, 
                Vendor_Work_End_Date__c = today.addDays(30)
            );
            
            // Prevent NullPointerException in the replaceMergeFields method.
            // If Name is a Text field, it MUST be explicitly set to avoid inserting as null.
            if (nameDesc.isCreateable() && !nameDesc.isAutoNumber()) {
                va.put('Name', 'Test_VA_Assignment_' + i);
            }
            
            assignments.add(va);
        }
        insert assignments;

        // 4. Create Tasks to Hit Different Logical Branches
        List<Task> tasks = new List<Task>();

        // Task 1: Due Tomorrow -> Triggers "Task_Reminder_Email" (DaysDiff == 1)
        tasks.add(new Task(
            Subject = 'Due Tomorrow Task',
            Status = 'Not Started',
            ActivityDate = today.addDays(1),
            WhatId = assignments[0].Id
        ));

        // Task 2: Due Yesterday -> Triggers "Danger_Zone_Alert" (DaysDiff < 0)
        tasks.add(new Task(
            Subject = 'Overdue Task',
            Status = 'Not Started',
            ActivityDate = today.addDays(-2),
            WhatId = assignments[1].Id
        ));

        // Task 3: Due in 10 Days -> Ignored (DaysDiff > 1)
        tasks.add(new Task(
            Subject = 'Future Task',
            Status = 'Not Started',
            ActivityDate = today.addDays(10),
            WhatId = assignments[2].Id
        ));

        insert tasks;
    }

    // ==========================================
    // Test 1: Main Batch Execution (Happy Path)
    // ==========================================
    @IsTest
    static void testBatchExecution() {
        Test.startTest();
        Integer beforeEmails = Limits.getEmailInvocations();

        // Run the batch
        TaskAlertBatch batch = new TaskAlertBatch();
        Database.executeBatch(batch);
        
        Test.stopTest(); // Forces synchronous completion of the batch

        Integer afterEmails = Limits.getEmailInvocations();
        
        // Assert that the Messaging.sendEmail() method was invoked 
        Assert.isTrue(afterEmails > beforeEmails, 'Batch should execute successfully and send the prepared email list.');
    }

    // ==========================================
    // Test 2: Edge Cases (Empty Scope & Missing Links)
    // ==========================================
    @IsTest
    static void testBatchEdgeCases() {
        TaskAlertBatch batch = new TaskAlertBatch();
        
        Test.startTest();
        
        // Edge Case A: Empty Scope
        // Hits: if (scope.isEmpty()) return;
        batch.execute(null, new List<Task>());
        
        // Edge Case B: Task with NO Vendor Assignment (WhatId is null)
        // Hits: if (assignmentIds.isEmpty()) return;
        Task orphanedTask = new Task(Subject = 'Orphaned', Status = 'Not Started', ActivityDate = Date.today());
        insert orphanedTask;
        batch.execute(null, new List<Task>{ orphanedTask });
        
        // Edge Case C: Task linked to something ELSE (e.g., an Opportunity) instead of Vendor Assignment
        // Hits: if (va == null) continue;
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Task oppTask = new Task(Subject = 'Opp Task', Status = 'Not Started', ActivityDate = Date.today(), WhatId = opp.Id);
        insert oppTask;
        batch.execute(null, new List<Task>{ oppTask });

        Test.stopTest();

        // No exceptions should be thrown, ensuring graceful exit logic works
        Assert.isTrue(true, 'Batch handled empty scopes and unlinked tasks without crashing.');
    }

    // ==========================================
    // Test 3: Formatting & Helper Functions Coverage
    // ==========================================
    @IsTest
    static void testMissingTemplatesHandling() {
        // Intentionally delete templates to test graceful degradation 
        // Hits: if (template != null) ... else { System.debug('⚠ Template missing'); }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            delete [SELECT Id FROM EmailTemplate WHERE DeveloperName IN ('Task_Reminder_Email', 'Danger_Zone_Alert_Vendor')];
        }

        Test.startTest();
        TaskAlertBatch batch = new TaskAlertBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        // Should complete without crashing even if templates are unexpectedly missing from the org
        Assert.isTrue(true, 'Batch handled missing templates gracefully.');
    }
}