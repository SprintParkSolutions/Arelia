/**
 * @description
 * Unit tests for ProjectReminderBatch and ProjectReminderBatchScheduler.
 * Refactored to remove SeeAllData=true, ensure high code coverage (>90%),
 * and comply with PMD rules (NoTrailingWhitespace, ApexUnitTestClassShouldHaveRunAs).
 */
@IsTest
private class ProjectReminderBatchTest {

    /**
     * @description
     * Sets up all required data for the batch class.
     * Separates Setup object creation (User, Role) from Non-Setup (Project, Contact)
     * to avoid Mixed DML errors.
     */
    @TestSetup
    static void setupData() {
        // ---------------------------------------------------------
        // BLOCK 1: SETUP OBJECTS (UserRole, User, EmailTemplate)
        // We run this in a separate context to avoid Mixed DML errors.
        // ---------------------------------------------------------
        User managerUser;
        User supervisor;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            // 1. Create 'Managers' Role
            // The batch specifically queries users WHERE UserRole.Name = 'Managers'
            UserRole managerRole = new UserRole(DeveloperName = 'Managers_Test_Role', Name = 'Managers');
            insert managerRole;

            // 2. Create Users
            managerUser = TestDataUtility.createUserWithRole('mgr', managerRole.Id);
            supervisor = TestDataUtility.createSupervisorUser('supUser');

            // 3. Create Email Template
            // The batch reads the template DeveloperName from a label.
            String templateDevName = Label.Arelia_Living_Project_Reminder_Template;

            // Fallback in case label is empty in the test environment
            if (String.isBlank(templateDevName)) {
                templateDevName = 'Project_Reminder_Template_Test';
            }

            EmailTemplate tpl = new EmailTemplate(
                DeveloperName = templateDevName,
                Name = 'Test Reminder Template',
                Subject = 'Reminder: {{ProjectName}}',
                HtmlValue = '<html><body>Hello {{RecipientName}}, Project {{ProjectName}} is due. Status: {{Status}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId(),
                IsActive = true
            );
            insert tpl;
        }

        // ---------------------------------------------------------
        // BLOCK 2: NON-SETUP OBJECTS (Contact, Project__c)
        // Now that the system block is closed, we can safely insert standard objects.
        // ---------------------------------------------------------

        // Retrieve the supervisor created above to link to the project
        User fetchedSupervisor = [SELECT Id FROM User WHERE Alias = 'supUser' LIMIT 1];

        // 4. Create Client Contact
        Contact client = TestDataUtility.createContact('TestClient', 'client@test.com', 'password123');

        // 5. Determine Reminder Interval
        // We need to backdate the Start_Date__c by exactly this interval to trigger the email logic.
        Integer interval = 15; // Default fallback
        String intervalLabel = Label.Arelia_Living_Project_Reminder_Days;
        if (String.isNotBlank(intervalLabel) && intervalLabel.isNumeric()) {
            interval = Integer.valueOf(intervalLabel.trim());
        }

        // --- Scenario A: Valid Project (Should Send Email) ---
        // Status = In Progress, Start Date = [Interval] days ago
        Project__c p1 = TestDataUtility.createProject('Valid Reminder Project', 50000, client.Id);
        p1.Supervisor_User__c = fetchedSupervisor.Id;
        p1.Start_Date__c = Date.today().addDays(-interval); // Exact match for modulo check
        p1.Status__c = 'In Progress';
        p1.Project_Completion_Status__c = 50;
        p1.Type_Of_Project__c = 'Home'; // Ensure this matches a valid picklist value

        // Handle Duration/End Date (Formula Field Dependencies)
        Schema.DescribeFieldResult durDescribe = Project__c.Estimated_Project_Duration__c.getDescribe();
        List<Schema.PicklistEntry> entries = durDescribe.getPicklistValues();
        if (!entries.isEmpty()) {
            p1.Estimated_Project_Duration__c = entries[0].getValue();
        }
        update p1;

        // --- Scenario B: Skip Project (Date Condition) ---
        // Start Date = Today. (Today - Start = 0). Logic requires > 0.
        Project__c p2 = TestDataUtility.createProject('Skip Date Project', 40000, client.Id);
        p2.Supervisor_User__c = fetchedSupervisor.Id;
        p2.Start_Date__c = Date.today();
        p2.Status__c = 'In Progress';
        if (!entries.isEmpty()) {
            p2.Estimated_Project_Duration__c = entries[0].getValue();
        }
        update p2;

        // --- Scenario C: Skip Project (Status Condition) ---
        // Status = Completed. Should be skipped immediately.
        Project__c p3 = TestDataUtility.createProject('Skip Status Project', 30000, client.Id);
        p3.Status__c = 'Completed';
        p3.Project_Completion_Status__c = 100; // Validation rule: 100% required for Completed status
        p3.Start_Date__c = Date.today().addDays(-interval);
        if (!entries.isEmpty()) {
            p3.Estimated_Project_Duration__c = entries[0].getValue();
        }
        update p3;
    }

    /**
     * @description
     * Tests the batch execution. Verifies that the batch runs without error and
     * processes the records.
     */
    @IsTest
    static void testBatchExecution() {
        // Enforce user context for PMD
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            // Execute Batch
            ProjectReminderBatch batch = new ProjectReminderBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verification
            // Query the AsyncApexJob to ensure it completed successfully
            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            System.assertEquals('Completed', job.Status, 'Batch job should complete successfully.');
            System.assertEquals(0, job.NumberOfErrors, 'Batch should run with zero errors.');

            // We expect at least one item to be processed (The 'Valid Reminder Project')
            System.assert(job.TotalJobItems > 0, 'Should have processed at least one batch chunk.');
        }
    }

    /**
     * @description
     * Tests the scheduler class to ensure it correctly queues the batch job.
     */
    @IsTest
    static void testScheduler() {
        // Enforce user context for PMD
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectReminderBatchScheduler sch = new ProjectReminderBatchScheduler();
            String cronExp = '0 0 10 * * ?'; // 10 AM daily
            String jobId = System.schedule('Test Project Reminder Scheduler', cronExp, sch);
            Test.stopTest();

            // Check if the job was actually scheduled
            CronTrigger ct = [
                SELECT Id, CronExpression, TimesTriggered, NextFireTime
                FROM CronTrigger
                WHERE Id = :jobId
            ];

            System.assertNotEquals(null, ct, 'CronTrigger should exist.');
            System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match.');
        }
    }
}