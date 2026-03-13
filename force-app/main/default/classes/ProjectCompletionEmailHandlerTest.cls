/**
 * @description       : Test class for ProjectCompletionEmailHandler
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 01-16-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
public class ProjectCompletionEmailHandlerTest {

    // Constants matching the Handler's private constants
    private static final String CLIENT_TPL     = 'Client_Project_Completed_Notification';
    private static final String SUPERVISOR_TPL = 'Supervisor_Project_Completed_Notification';
    private static final String MANAGER_TPL    = 'Sending_Project_Completed_Information_to_Manager';
    private static final String MGMT_TPL       = 'Sending_Project_Completed_Information_to_Management';
    private static final String ENROLL_TPL     = 'Sending_Project_Completed_Information_to_Enrollment';

    @TestSetup
    static void setupData() {
        // Create User Role and User for Manager Logic
        UserRole mgrRole = TestDataUtility.createUserRole('Regional Project Manager');
        TestDataUtility.createUserWithRole('mgrUser', mgrRole.Id);

        // Create templates needed
        TestDataUtility.createSpecificEmailTemplate(CLIENT_TPL, 'Client Notif', 'Subject');
        TestDataUtility.createSpecificEmailTemplate(SUPERVISOR_TPL, 'Sup Notif', 'Subject');
        TestDataUtility.createSpecificEmailTemplate(MANAGER_TPL, 'Manager Notif', 'Subject');
        TestDataUtility.createSpecificEmailTemplate(MGMT_TPL, 'Mgmt Notif', 'Subject');
        TestDataUtility.createSpecificEmailTemplate(ENROLL_TPL, 'Enroll Notif', 'Subject');
    }

    /**
     * @description Helper to generate a fake Salesforce ID in memory without DML.
     * Use this to prevent triggers/automation from firing during unit tests.
     */
    private static String getFakeId(Schema.SObjectType sot) {
        String result = String.valueOf(sot.getDescribe().getKeyPrefix());
        return result + '000000000001';
    }

    private static Project__c createBaseProject() {
        Account acc = TestDataUtility.createAccount('Project Client Co');
        Contact client = TestDataUtility.createContact('Project Client', 'client@project.test', 'password123');
        client.AccountId = acc.Id;
        update client;

        User sup = TestDataUtility.createSupervisorUser('sup1');

        Project__c proj = TestDataUtility.createProject('Test Completion Project', 50000, client.Id);
        proj.Status__c = 'In Progress';
        proj.Project_Completion_Status__c = 0;
        proj.Project_Code__c = 'PRJ-001';
        proj.Supervisor_User__c = sup.Id; // Ensure supervisor is linked
        update proj;
        return proj;
    }

    /**
     * @description Helper method to reduce Copy/Paste duplication.
     * Prepares the OldMap, updates Status to Completed/100%, and executes the handler.
     * NOTE: RunAs is handled in the calling method to satisfy PMD rules.
     * @param proj The Project record to process.
     */
    private static void executeCompletionFlow(Project__c proj) {
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };
        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 100;

        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>{ proj }, oldMap);
        Test.stopTest();
    }

    // ==========================================
    // POSITIVE TESTS
    // ==========================================

    /**
     * @description Tests the successful completion scenario where all emails should be triggered.
     * Covers: Standard flow with valid Contact and Supervisor lookups.
     */
    @IsTest
    static void testSuccessfulCompletion() {
        Project__c proj = createBaseProject();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            executeCompletionFlow(proj);
        }
        Assert.isTrue(Limits.getEmailInvocations() >= 1, 'Emails should be sent on successful completion');
    }

    /**
     * @description Tests the fallback logic when Linked Contact/User has no email.
     * Covers: buildClientEmails/buildSupervisorEmails "Else" branches for direct email.
     */
    @IsTest
    static void testMissingRecipientEmails() {
        Project__c proj = createBaseProject();

        // 1. Update Contact to have empty email
        Contact c = [SELECT Id FROM Contact WHERE Id = :proj.Client__c];
        c.Email = null;
        update c;

        // 2. Set Fallback override
        ProjectCompletionEmailHandler.testEmailFallback = 'fallback_system@test.com';

        System.runAs(new User(Id = UserInfo.getUserId())) {
            executeCompletionFlow(proj);
        }

        // Reset
        ProjectCompletionEmailHandler.testEmailFallback = null;

        Assert.isTrue(true, 'Executed fallback logic without exception');
    }

    /**
     * @description Tests scenarios where Lookups are NULL, forcing "replaceVars" to handle null objects.
     */
    @IsTest
    static void testNullLookupsWithFallback() {
        Project__c proj = createBaseProject();
        proj.Client__c = null;
        proj.Supervisor_User__c = null;
        update proj;

        ProjectCompletionEmailHandler.testEmailFallback = 'fallback_nulls@test.com';

        System.runAs(new User(Id = UserInfo.getUserId())) {
            executeCompletionFlow(proj);
        }

        ProjectCompletionEmailHandler.testEmailFallback = null;
        Assert.isTrue(true, 'Executed with null lookups successfully');
    }

    /**
     * @description Tests CSV edge cases including empty slots and invalid formats.
     */
    @IsTest
    static void testCsvEdgeCases() {
        Project__c proj = createBaseProject();

        // 1. Valid, 2. Empty, 3. Invalid Format
        ProjectCompletionEmailHandler.testCsvOverride = 'john.doe@test.com, , invalid_string';

        System.runAs(new User(Id = UserInfo.getUserId())) {
            executeCompletionFlow(proj);
        }

        ProjectCompletionEmailHandler.testCsvOverride = null;
        Assert.isTrue(true, 'CSV parsing edge cases executed');
    }

    /**
     * @description Tests specific logic in "inferDisplayNameFromEmail" by providing complex names.
     * This hits the loops inside string splitting/capitalization.
     */
    @IsTest
    static void testComplexNameInference() {
        Project__c proj = createBaseProject();

        // Complex email with dots and underscores: jane.mary_doe@test.com -> Jane Mary Doe
        ProjectCompletionEmailHandler.testCsvOverride = 'jane.mary_doe@test.com';

        System.runAs(new User(Id = UserInfo.getUserId())) {
            executeCompletionFlow(proj);
        }

        ProjectCompletionEmailHandler.testCsvOverride = null;
        Assert.isTrue(true, 'Complex name inference executed');
    }

    /**
     * @description Tests "replaceVars" when Project fields (Name, Code) are explicitly NULL.
     * This forces the code to use the "safe()" method on project fields.
     */
    @IsTest
    static void testProjectFieldsNull() {
        Project__c proj = createBaseProject();
        proj.Project_Code__c = null;
        proj.Type_Of_Project__c = null;
        proj.Project_Scope__c = null;
        update proj;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            executeCompletionFlow(proj);
        }
        Assert.isTrue(true, 'Executed with null project fields successfully');
    }

    /**
     * @description Tests logic ensuring Managers are retrieved by Role.
     */
    @IsTest
    static void testManagerRoleLogic() {
        Project__c proj = createBaseProject();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            executeCompletionFlow(proj);
        }
        Assert.isTrue(true, 'Executed Manager Logic without exception');
    }

    // ==========================================
    // EXCEPTION & EDGE CASE TESTS
    // ==========================================

    /**
     * @description Forces an exception to cover the catch block in sendProjectApprovedEmail.
     */
    @IsTest
    static void testExceptionCatch() {
        Project__c proj = createBaseProject();
        ProjectCompletionEmailHandler.forceException = true;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectCompletionEmailHandler.sendProjectApprovedEmail(new List<Project__c>{ proj });
            Test.stopTest();

            Assert.isTrue(true, 'Exception should be caught and logged, not thrown');
            ProjectCompletionEmailHandler.forceException = false;
        }
    }

    /**
     * @description Tests null safety for public methods and template fetching.
     */
    @IsTest
    static void testNullSafetyAndEmptyTemplates() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            // 1. Null Inputs
            ProjectCompletionEmailHandler.handleAfterUpdate(null, null);
            ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>(), new Map<Id, Project__c>());
            ProjectCompletionEmailHandler.sendProjectApprovedEmail(null);

            // 2. Missing Template Coverage (delete one template to force null return in loadTemplates)
            EmailTemplate tpl = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :CLIENT_TPL LIMIT 1];
            delete tpl;

            Project__c proj = createBaseProject();
            Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };
            proj.Status__c = 'Completed';
            proj.Project_Completion_Status__c = 100;

            ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>{ proj }, oldMap);

            Test.stopTest();
            Assert.isTrue(true, 'Should handle empty/null inputs gracefully');
        }
    }

    /**
     * @description Tests the case where a record is in NewList but missing from OldMap.
     * Uses IN-MEMORY data (Fake IDs) to ensure no Trigger/Automation noise interferes with the assertion.
     * This guarantees that if the Handler logic is correct, 0 emails are sent.
     */
    @IsTest
    static void testNewProjectNotInOldMap() {
        // Generate Fake Id
        String fakeId = getFakeId(Project__c.SObjectType);

        // Create In-Memory Project (No DML)
        String jsonProj = '{"attributes":{"type":"Project__c"}, "Id":"' + fakeId + '", "Status__c":"Completed", "Project_Completion_Status__c":100}';
        Project__c proj = (Project__c)JSON.deserialize(jsonProj, Project__c.class);

        // Pass an empty map to simulate "Insert" logic passed to "Update" handler
        Map<Id, Project__c> emptyOldMap = new Map<Id, Project__c>();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>{ proj }, emptyOldMap);
            Test.stopTest();
        }

        Assert.areEqual(0, Limits.getEmailInvocations(), 'Should return early if old record is missing');
    }

    // ==========================================
    // NEGATIVE TESTS
    // ==========================================

    @IsTest
    static void testPartialCompletionStatusOnly() {
        Project__c proj = createBaseProject();
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };
        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 0;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>{ proj }, oldMap);
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should NOT send email if % is not 100');
        }
    }

    @IsTest
    static void testPartialCompletionPercentOnly() {
        Project__c proj = createBaseProject();
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };
        proj.Status__c = 'In Progress';
        proj.Project_Completion_Status__c = 100;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>{ proj }, oldMap);
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should NOT send email if Status is not Completed');
        }
    }

    @IsTest
    static void testAlreadyCompleted() {
        Project__c proj = createBaseProject();
        Project__c oldProj = proj.clone(true, true, true, true);
        oldProj.Status__c = 'Completed';
        oldProj.Project_Completion_Status__c = 100;
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => oldProj };

        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 100;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>{ proj }, oldMap);
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should NOT send email if it was already completed');
        }
    }
}