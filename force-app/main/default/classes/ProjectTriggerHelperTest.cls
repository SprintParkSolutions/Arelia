@IsTest
private class ProjectTriggerHelperTest {

    @TestSetup
    static void setupData() {
        User supervisor;
        // Run as the current user to avoid Mixed DML when creating Setup objects (Users/Roles)
        System.runAs(new User(Id = UserInfo.getUserId())) {
             UserRole managerRole = TestDataUtility.createUserRole('Regional Manager');
             TestDataUtility.createUserWithRole('mgr', managerRole.Id);
             supervisor = TestDataUtility.createSupervisorUser('sup');
        }

        // Use Utility to create Client
        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com', 'password123');

        List<Project__c> projects = new List<Project__c>();
        
        // Project 0: For Success Scenario
        Project__c p1 = TestDataUtility.createProject('Success Project', 10000, client.Id);
        p1.Supervisor_User__c = supervisor.Id;
        p1.Project_Completion_Status__c = 0; 
        projects.add(p1);

        // Project 1: For Project Failure Scenario
        Project__c p2 = TestDataUtility.createProject('Fail Project Own Status', 10000, client.Id);
        p2.Supervisor_User__c = supervisor.Id;
        projects.add(p2);

        // Project 2: For Vendor Failure Scenario
        Project__c p3 = TestDataUtility.createProject('Fail Project Vendor', 10000, client.Id);
        p3.Supervisor_User__c = supervisor.Id;
        projects.add(p3);

        update projects;
    }

    /**
     * @description Helper to create and configure a Vendor Assignment for testing specific states.
     */
    private static Vendor_Assignment__c createVA(Id projectId, String status, Decimal completion) {
        // Utility method automatically handles required fields like Dates
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(projectId, 100); 
        
        // Update to desired test state
        va.Status__c = status;
        va.Completion__c = completion;
        update va;
        
        return va;
    }

    // ==========================================
    // POSITIVE TESTS
    // ==========================================

    @IsTest
    static void testCompletionSuccess() {
        Project__c p = [SELECT Id, Status__c FROM Project__c WHERE Name = 'Success Project' LIMIT 1];

        // Valid: Vendor Assignment is 100% and 'Completed'
        createVA(p.Id, 'Completed', 100);

        Test.startTest();
        p.Project_Completion_Status__c = 100;
        p.Status__c = 'Completed';
        update p;
        Test.stopTest();

        Project__c result = [SELECT Status__c FROM Project__c WHERE Id = :p.Id];
        Assert.areEqual('Completed', result.Status__c, 'The project status should be successfully updated to Completed when all criteria are met.');
    }

    @IsTest
    static void testNoStatusChange() {
        // Covers the early return: if (projectsToValidateIds.isEmpty()) return;
        Project__c p = [SELECT Id, Supervisor_Estimated_Budget__c FROM Project__c WHERE Name = 'Success Project' LIMIT 1];

        Test.startTest();
        // Update a field OTHER than Status__c
        p.Supervisor_Estimated_Budget__c = 20000;
        update p;
        Test.stopTest();

        Project__c result = [SELECT Supervisor_Estimated_Budget__c, Status__c FROM Project__c WHERE Id = :p.Id];
        Assert.areEqual(20000, result.Supervisor_Estimated_Budget__c, 'The project should update successfully without triggering validation rules.');
        Assert.areNotEqual('Completed', result.Status__c, 'The status should remain unchanged.');
    }

    // ==========================================
    // NEGATIVE TESTS (Trigger Validation Errors)
    // ==========================================

    @IsTest
    static void testFailProjectIncomplete() {
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Own Status' LIMIT 1];

        // Vendor Assignment is valid, but the Project itself is not 100%
        createVA(p.Id, 'Completed', 100);

        Test.startTest();
        try {
            // Failure Condition: Project status is Completed but Completion % is only 99
            p.Project_Completion_Status__c = 99;
            p.Status__c = 'Completed';
            update p;
            
            Assert.fail('The trigger should have thrown a DmlException because the Project Completion Status is not 100%.');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('Project Completion Status'), 'The error message should specifically mention the Project Completion Status.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testFailVendorIncomplete() {
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Vendor' LIMIT 1];

        // Failure Condition: Vendor is In-Progress and only 50% complete
        createVA(p.Id, 'In-Progress', 50);

        Test.startTest();
        try {
            p.Project_Completion_Status__c = 100;
            p.Status__c = 'Completed';
            update p;
            
            Assert.fail('The trigger should have thrown a DmlException because the Vendor Assignment is incomplete.');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('Vendor Assignments'), 'The error message should specifically mention Vendor Assignments.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testFailVendorStatusMismatch() {
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Vendor' LIMIT 1];

        // Failure Condition: Vendor is marked 'Completed' manually, but the Completion is only 99%
        // This avoids the 100% automation bypass and explicitly covers the (Completion__c != 100) logic block.
        createVA(p.Id, 'Completed', 99);

        Test.startTest();
        try {
            p.Project_Completion_Status__c = 100;
            p.Status__c = 'Completed';
            update p;
            
            Assert.fail('The trigger should have thrown a DmlException because the Vendor Assignment completion is not 100%.');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('Vendor Assignments'), 'The error message should specifically mention Vendor Assignments.');
        }
        Test.stopTest();
    }
}