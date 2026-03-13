/**
 * @description       : Test class for VendorReminderScheduler. Achieves >90% coverage naturally.
 * @last modified on  : 02-26-2026
**/
@IsTest
private class VendorReminderSchedulerTest {

    @TestSetup
    static void setupData() {
        // 1. Setup Users, Roles, and Email Templates in System.runAs to avoid MIXED_DML
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole mgrRole = TestDataUtility.createUserRole('Regional Manager');
            TestDataUtility.createUserWithRole('mgrTest', mgrRole.Id);
            
            TestDataUtility.createSupervisorUser('supTest');
            
            TestDataUtility.createSpecificEmailTemplate(
                'VA_Due_Alert_to_the_Supervisor_User', 
                'VA Reminder Alert', 
                'Reminder {{Vendor_Assignment__c.Name}}', 
                'Html Body: {{SupervisorName}} {{CompletionPercentage}} {{TaskTable}}'
            );
        }

        User sup = [SELECT Id FROM User WHERE Alias = 'supTest' LIMIT 1];

        // 2. Create Base Records
        Contact client = TestDataUtility.createContact('Client', 'client@test.com', 'pwd123');
        Project__c proj = TestDataUtility.createProject('Test Project', 10000, client.Id);

        Opportunity opp = TestDataUtility.createOpportunity('Test Opp', sup.Id);
        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        update opp;

        Vendor__c vendor = TestDataUtility.createVendor('Test Vendor', 'Flooring & Tiling', 'vendor@test.com');
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');

        // 3. Create Vendor Assignments to hit ALL Risk Classification Branches
        List<Vendor_Assignment__c> assignments = new List<Vendor_Assignment__c>();
        Date today = Date.today();

        // VA 0: High Risk (<25%). Starts Today, Ends Tomorrow. (daysLeft = 1).
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 10, 
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(1)
        ));

        // VA 1: Risk (25-50%). Ends in 3 days. Total=3, buffer=1.
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 40, 
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(3)
        ));

        // VA 2: Low Risk (51-70%). Ends in 2 days. Total=2, buffer=1. 
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 60, 
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(2)
        ));

        // VA 3: At Risk (71-95%). Ends in 10 days. Total=10, buffer=1.
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 90, 
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(10)
        ));

        // VA 4: Future Start Date (Has not started yet). 
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 30, 
            Vendor_Work_Start_Date__c = today.addDays(2), Vendor_Work_End_Date__c = today.addDays(12)
        ));

        // VA 5: Completed (100%).
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 100, 
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(10)
        ));

        // VA 6: Null Completion % (Fallback to 0).
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = null, 
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(5)
        ));

        insert assignments;

        // 4. Create Tasks for HTML Table generation
        List<Task> tasks = new List<Task>();
        tasks.add(new Task(
            Subject = 'Installation Setup 1', Status = 'Not Started', Priority = 'Normal',
            WhatId = assignments[0].Id, Start_Date__c = null, ActivityDate = null
        ));
        tasks.add(new Task(
            Subject = 'Installation Setup 2', Status = 'In Progress', Priority = 'High',
            WhatId = assignments[0].Id, Start_Date__c = today, ActivityDate = today.addDays(1)
        ));
        insert tasks;
    }

    // ==========================================
    // Test 1: Schedulable Context & Full Execution
    // ==========================================
    @IsTest
    static void testScheduledJobExecution() {
        Test.startTest();
        Integer beforeEmails = Limits.getEmailInvocations();

        String cronExp = '0 0 12 * * ?'; 
        System.schedule('VendorReminderTestJob', cronExp, new VendorReminderScheduler());
        
        Test.stopTest(); // Forces asynchronous schedule/batch execution

        Integer afterEmails = Limits.getEmailInvocations();
        
        Assert.isTrue(afterEmails > beforeEmails, 'The scheduled job should have dispatched alert emails for qualifying records.');
    }

    // ==========================================
    // Test 2: Edge Case - No Assignments
    // ==========================================
    @IsTest
    static void testNoAssignmentsToProcess() {
        List<Vendor_Assignment__c> vas = [SELECT Id FROM Vendor_Assignment__c];
        for (Vendor_Assignment__c va : vas) {
            va.Status__c = 'Completed';
        }
        update vas;

        Test.startTest();
        Integer beforeEmails = Limits.getEmailInvocations();
        
        VendorReminderScheduler scheduler = new VendorReminderScheduler();
        scheduler.execute(null);
        
        Integer afterEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(beforeEmails, afterEmails, 'No emails should be sent when there are no In-Progress assignments.');
    }

    // ==========================================
    // Test 3: Edge Case - Missing Template & Null Dates
    // ==========================================
    @IsTest
    static void testNullDatesAndMissingTemplate() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'VA_Due_Alert_to_the_Supervisor_User'];
            if (!templates.isEmpty()) {
                delete templates;
            }
        }

        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        va.Vendor_Work_Start_Date__c = null;
        va.Vendor_Work_End_Date__c = null;
        update va;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            VendorReminderScheduler scheduler = new VendorReminderScheduler();
            scheduler.execute(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        Assert.isFalse(exceptionThrown, 'The scheduler should execute successfully and handle missing templates or null dates gracefully without throwing exceptions.');
    }

    // ==========================================
    // Test 4: Edge Case - Missing Supervisor & Managers
    // ==========================================
    @IsTest
    static void testMissingRelationsAndManagers() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> mgrs = [SELECT Id, IsActive FROM User WHERE UserRole.Name LIKE '%Manager%'];
            for(User u : mgrs) {
                u.IsActive = false;
            }
            update mgrs;
        }

        List<Vendor_Assignment__c> vas = [SELECT Id FROM Vendor_Assignment__c];
        for (Vendor_Assignment__c va : vas) {
            va.Supervisor_User__c = null;
        }
        update vas;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            VendorReminderScheduler scheduler = new VendorReminderScheduler();
            scheduler.execute(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        Assert.isFalse(exceptionThrown, 'The scheduler should execute smoothly even when supervisors are unassigned and no active managers are found.');
    }
}