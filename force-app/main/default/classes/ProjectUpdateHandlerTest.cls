@IsTest
private class ProjectUpdateHandlerTest {

    /**
     * @description Helper to get Client Template DeveloperName dynamically.
     */
    private static String getClientTemplateDevName() {
        String labelVal = Label.Arelia_Living_Project_Status_Update_Lead_Template;
        return String.isNotBlank(labelVal) ? labelVal : 'Test_Client_Template';
    }

    /**
     * @description Helper to get Supervisor Template DeveloperName dynamically.
     */
    private static String getSupervisorTemplateDevName() {
        String labelVal = Label.Arelia_Living_Project_Status_Update_Supervisor_Template;
        return String.isNotBlank(labelVal) ? labelVal : 'Test_Supervisor_Template';
    }

    /**
     * @description Sets up the test data including Users, Contacts, Projects, and Templates.
     */
    @TestSetup
    static void setupData() {
        // 1. Create Users & Contacts
        User supervisor = TestDataUtility.createSupervisorUser('supUser');
        TestDataUtility.createContact('Dummy Contact', 'dummy@arelia.test', 'pass123');
        Contact client = TestDataUtility.createContact('Real Client', 'client@arelia.test', 'pass123');

        // 2. Create Project
        Project__c proj = TestDataUtility.createProject('Test Project Coverage', 10000, client.Id);
        proj.Supervisor_User__c = supervisor.Id;
        proj.Project_Completion_Status__c = 0;
        update proj;

        // 3. Create Templates (Run as admin to avoid Mixed DML)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                getClientTemplateDevName(), 
                'Client Update', 
                'Status Update: {{Project__c.Name}}', 
                'Project status is now {{Project__c.Project_Completion_Status__c}}'
            );
            
            TestDataUtility.createSpecificEmailTemplate(
                getSupervisorTemplateDevName(), 
                'Supervisor Update', 
                'Status Update: {{Project__c.Name}}', 
                'Project status is now {{Project__c.Project_Completion_Status__c}}'
            );
        }
    }

    // ============================================================================
    // POSITIVE TESTS
    // ============================================================================

    /**
     * @description Verifies that a change in Project_Completion_Status__c triggers emails.
     */
    @IsTest
    static void testStatusChangeSendsEmails() {
        // Query the project to ensure formula fields (Emails) are populated by the database
        Project__c proj = [
            SELECT Id, Name, Project_Completion_Status__c, Client_Email__c, Supervisor_Email_Text_c__c 
            FROM Project__c 
            LIMIT 1
        ];

        // Clone preserves Id and formula fields in memory
        Project__c oldProj = proj.clone(true, true, true, true);
        Project__c newProj = proj.clone(true, true, true, true);
        
        // Trigger the change condition
        newProj.Project_Completion_Status__c = 50;

        List<Project__c> newList = new List<Project__c>{ newProj };
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ oldProj.Id => oldProj };

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        
        // Directly invoke the handler
        ProjectUpdateHandler.afterUpdate(newList, oldMap);
        
        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        // 1 Client Email + 1 Supervisor Email = 2 Emails (or 1 invocation processing a batch of 2)
        Assert.isTrue(emailsAfter > emailsBefore, 'Email invocations should increase after a status change.');
    }

    // ============================================================================
    // NEGATIVE TESTS & EDGE CASES
    // ============================================================================

    /**
     * @description Verifies that no emails are sent if the required EmailTemplates are missing.
     */
    @IsTest
    static void testNegativeMissingTemplates() {
        Project__c proj = [SELECT Id, Client_Email__c, Supervisor_Email_Text_c__c FROM Project__c LIMIT 1];

        // Remove the templates
        System.runAs(new User(Id = UserInfo.getUserId())) {
            delete [SELECT Id FROM EmailTemplate WHERE DeveloperName IN (:getClientTemplateDevName(), :getSupervisorTemplateDevName())];
        }

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        ProjectUpdateHandler.sendProjectStatusUpdateEmails(new List<Project__c>{ proj });
        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(emailsBefore, emailsAfter, 'No emails should be sent when the required templates are missing.');
    }

    /**
     * @description Verifies that no emails are sent if the dummy contact is missing.
     */
    @IsTest
    static void testNegativeMissingContact() {
        Project__c proj = [SELECT Id, Client_Email__c, Supervisor_Email_Text_c__c FROM Project__c LIMIT 1];

        // Delete ALL contacts so getSharedDummyContact() returns null
        delete [SELECT Id FROM Contact];

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        ProjectUpdateHandler.sendProjectStatusUpdateEmails(new List<Project__c>{ proj });
        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(emailsBefore, emailsAfter, 'No emails should be sent when the dummy TargetObject contact is missing.');
    }

    /**
     * @description Verifies behavior when the old record is missing from the map (Orphaned Record).
     */
    @IsTest
    static void testOrphanedOldRecord() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        List<Project__c> newList = new List<Project__c>{ proj };
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>(); // Empty old map

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        ProjectUpdateHandler.afterUpdate(newList, oldMap);
        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(emailsBefore, emailsAfter, 'No emails should be sent if the old record map does not contain the project.');
    }

    /**
     * @description Verifies that no emails are sent if the status field has NOT changed.
     */
    @IsTest
    static void testNoStatusChange() {
        Project__c proj = [SELECT Id, Project_Completion_Status__c FROM Project__c LIMIT 1];
        
        // Both maps have the exact same status
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj };
        List<Project__c> newList = new List<Project__c>{ proj };

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        ProjectUpdateHandler.afterUpdate(newList, oldMap);
        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(emailsBefore, emailsAfter, 'No emails should be sent if the completion status remained unchanged.');
    }

    /**
     * @description Verifies that guard clauses handle null inputs gracefully without throwing exceptions.
     */
    @IsTest
    static void testGuardClausesAndNulls() {
        Test.startTest();
        
        // Pass nulls and empty lists to trigger early returns
        ProjectUpdateHandler.afterUpdate(null, null);
        ProjectUpdateHandler.afterUpdate(new List<Project__c>(), null);
        ProjectUpdateHandler.sendProjectStatusUpdateEmails(null);
        ProjectUpdateHandler.sendProjectStatusUpdateEmails(new List<Project__c>());

        // List containing a null project
        ProjectUpdateHandler.sendProjectStatusUpdateEmails(new List<Project__c>{ null });
        
        Test.stopTest();

        Assert.isTrue(true, 'Guard clauses should handle nulls and empty lists gracefully without throwing NullPointerExceptions.');
    }
}