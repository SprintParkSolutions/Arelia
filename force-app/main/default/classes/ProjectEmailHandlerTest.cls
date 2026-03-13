@isTest
public class ProjectEmailHandlerTest {

    @testSetup
    static void setupData() {
        // 1. Create User (Supervisor) using Utility
        User supervisor = TestDataUtility.createSupervisorUser('supuser');

        // 2. Create Prerequisites (Account & Contact) using Utility
        // Utility createProject requires a Contact ID.
        Account acc = TestDataUtility.createAccount('Test Project Account');
        
        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com', 'password123');
        client.AccountId = acc.Id;
        update client;

        // 3. Create Project using Utility (requires Name, Budget, ContactId)
        Project__c proj = TestDataUtility.createProject('Test Project Alpha', 50000, client.Id);
        
        // Update Project with additional fields specific to this test logic
        proj.Client_Email__c = client.Email; 
        proj.Supervisor_User__c = supervisor.Id;
        update proj;

        // 4. Create Required Email Templates using Utility
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                'Project_To_Lead', 
                'Project To Lead', 
                'Project Update for Client'
            );
            TestDataUtility.createSpecificEmailTemplate(
                'Project_To_IDC', 
                'Project To IDC', 
                'Project Update for Mgmt'
            );
        }
    }

    @isTest
    static void testSendEmailForProjectPositive() {
        // Fetch the project created in Setup
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        // Capture baseline before running logic
        Integer startCount = Limits.getEmailInvocations();
        
        // Execute the handler
        ProjectEmailHandler.sendEmailForProject(proj);
        
        // Capture count after logic
        Integer endCount = Limits.getEmailInvocations();
        Test.stopTest();

        // Check the difference (Delta)
        System.assert((endCount - startCount) >= 1, 'Should have sent at least 1 email (Client Email)');
    }

    @isTest
    static void testSendEmailForProjectNullProject() {
        Test.startTest();
        Integer startCount = Limits.getEmailInvocations();
        
        try {
            ProjectEmailHandler.sendEmailForProject(null);
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception for null project, should return gracefully');
        }
        
        Integer endCount = Limits.getEmailInvocations();
        Test.stopTest();
        
        // Assert that OUR code sent 0 emails (ignoring background noise)
        System.assertEquals(0, (endCount - startCount), 'No emails should be sent for null project');
    }

    @isTest
    static void testSendEmailForProjectMissingClientInfo() {
        // Fetch project and remove client info
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        proj.Client__c = null;
        proj.Client_Email__c = null;
        update proj;

        Test.startTest();
        ProjectEmailHandler.sendEmailForProject(proj);
        Test.stopTest();

        // The test ensures the code doesn't crash when Client info is missing.
        System.assert(true, 'Code executed successfully without exception');
    }
    
    @isTest
    static void testSendEmailForProjectMissingTemplates() {
        // Delete the templates created in Setup to simulate missing configuration
        delete [SELECT Id FROM EmailTemplate WHERE DeveloperName IN ('Project_To_Lead', 'Project_To_IDC')];
        
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        Integer startCount = Limits.getEmailInvocations();
        
        ProjectEmailHandler.sendEmailForProject(proj);
        
        Integer endCount = Limits.getEmailInvocations();
        Test.stopTest();

        // Should be 0 because template queries will return null
        System.assertEquals(0, (endCount - startCount), 'No emails should be sent if templates are missing');
    }
}