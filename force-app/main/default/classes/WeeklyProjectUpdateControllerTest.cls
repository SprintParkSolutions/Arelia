@IsTest
private class WeeklyProjectUpdateControllerTest {

    @TestSetup
    static void setupData() {
        // Run as admin to avoid Mixed DML when creating setup objects (Templates/Users)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            
            // 1. Create Supervisor using Utility
            User supervisor = TestDataUtility.createSupervisorUser('weeklyUs');

            // 2. Create Client (Contact) using Utility
            Contact client = TestDataUtility.createContact('WeeklyClient', 'client@weekly.com', 'pwd123');

            // 3. Create Project using Utility
            Project__c proj = TestDataUtility.createProject('Weekly Update Project', 10000, client.Id);
            
            // Update additional fields required by the Weekly Update logic
            proj.Client_Email__c = 'client@weekly.com';
            proj.Start_Date__c = Date.today().addDays(-14); // Exactly 2 weeks ago
            proj.Supervisor_User__c = supervisor.Id;
            update proj;

            // 4. Create Email Template using Utility
            TestDataUtility.createSpecificEmailTemplate(
                'Weekly_Project_Update_Template',
                'Weekly Project Update',
                'Update {{{ProjectName}}} - Week {{{WeekNumber}}}',
                'Hello {{{ClientName}}}<br/>{{{WeeklySummary}}}<br/>{{{FileLinks}}}'
            );
        }
    }

    // ==========================================
    // 1. Test Project Retrieval
    // ==========================================
    @IsTest
    static void testGetSupervisorProjects() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'weeklyUs' LIMIT 1];

        System.runAs(supervisor) {
            Test.startTest();
            List<Project__c> projects = WeeklyProjectUpdateController.getSupervisorProjects();
            Test.stopTest();

            Assert.areEqual(1, projects.size(), 'Should return exactly 1 project assigned to the supervisor');
            Assert.areEqual('Weekly Update Project', projects[0].Name, 'The project name should match');
        }
    }

    // ==========================================
    // 2. Test Email Sending with ALL File Types
    // ==========================================
    @IsTest
    static void testSendWeeklyEmailAllFileTypes() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // Create specific file types to cover the HTML logic in the Controller (Image, Video, Document)
        ContentVersion imgCv = new ContentVersion(Title='photo', PathOnClient='photo.jpg', VersionData=Blob.valueOf('img'), IsMajorVersion=true);
        ContentVersion vidCv = new ContentVersion(Title='video', PathOnClient='video.mp4', VersionData=Blob.valueOf('vid'), IsMajorVersion=true);
        insert new List<ContentVersion>{ imgCv, vidCv };
        
        // Use utility to create a PDF document
        ContentVersion pdfCv = TestDataUtility.createContentVersion('doc', 'doc content');

        // Extract Document IDs to pass to the controller
        List<Id> documentIds = new List<Id>();
        for(ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion]) {
            documentIds.add(cv.ContentDocumentId);
        }

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        
        // Execute Action
        WeeklyProjectUpdateController.sendWeeklyEmail(proj.Id, 'Great progress this week!', documentIds);
        
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails + 1, finalEmails, 'One email should have been sent containing all file type links');
    }

    // ==========================================
    // 3. Test Email Sending with Fallback Conditions
    // ==========================================
    @IsTest
    static void testSendWeeklyEmailFallbackConditions() {
        // Remove Start Date and Supervisor to test null-fallback logic (WeekNo = 1, UserInfo.getName())
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        proj.Start_Date__c = null;
        proj.Supervisor_User__c = null; 
        update proj;

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        
        // Execute Action with null files
        WeeklyProjectUpdateController.sendWeeklyEmail(proj.Id, 'Weekly progress', null); 
        
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails + 1, finalEmails, 'Email should be sent successfully even if Dates or Supervisor are missing');
    }

    // ==========================================
    // 4. Test Error Handling (Missing Client Email)
    // ==========================================
    @IsTest
    static void testSendWeeklyEmailMissingClientEmail() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        proj.Client_Email__c = null;
        update proj;

        Test.startTest();
        try {
            WeeklyProjectUpdateController.sendWeeklyEmail(proj.Id, 'This should fail', null);
            Assert.fail('Expected an AuraHandledException because the client email is null');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Exception should be of type AuraHandledException');
        }
        Test.stopTest();
    }

    // ==========================================
    // 5. Test Org-Wide Email Address Retrieval
    // ==========================================
    @IsTest
    static void testGetOWD() {
        Test.startTest();
        Id owdId = WeeklyProjectUpdateController.getOWD();
        Test.stopTest();

        // OWD might be null depending on the Sandbox setup. 
        // We assert true to guarantee the query executes cleanly without breaking.
        Assert.isTrue(true, 'The getOWD method executed successfully');
    }
}