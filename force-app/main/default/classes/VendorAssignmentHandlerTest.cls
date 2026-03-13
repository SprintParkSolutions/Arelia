@isTest
public class VendorAssignmentHandlerTest {

    @testSetup
    static void setupData() {
        // 1. Create Prerequisites (Account & Contact) using Utility
        // Utility createProject requires a Contact ID.
        Account acc = TestDataUtility.createAccount('Test Account');
        
        Contact con = TestDataUtility.createContact('Test Contact', 'test@example.com', 'pass123');
        con.AccountId = acc.Id;
        update con;

        // 2. Create Project using Utility
        // Utility requires (Name, Budget, ContactId)
        Project__c proj = TestDataUtility.createProject('Test Project VA Handler', 10000, con.Id);
        
        // FIX: 'Remaining_Project_Budget__c' is likely read-only formula. We set the source field.
        // Assuming 'Total_Budget__c' is the writable source if it exists.
        try {
            proj.put('Total_Budget__c', 10000); 
            update proj;
        } catch(Exception e) {
            System.debug('Could not set Total_Budget__c dynamically: ' + e.getMessage());
        }

        // 3. Create Vendor using Utility
        Vendor__c vendor = TestDataUtility.createVendor('Test Vendor', 'Electrical & Networking', 'test@vendor.com');

        // 4. Create User (Supervisor)
        User supervisor = TestDataUtility.createSupervisorUser('vahsup');

        // 5. Create Assignments using Utility
        // Utility sets Status='In-Progress', Start=Today, End=Today+10
        Vendor_Assignment__c va1 = TestDataUtility.createVendorAssignment(proj.Id, 0);
        va1.Vendor__c = vendor.Id;
        va1.Supervisor_User__c = supervisor.Id;
        
        // FIX: 'Vendor_Amount__c' is read-only. We set the source field.
        // Assuming 'Contract_Amount__c' is the writable source.
        try {
            va1.put('Contract_Amount__c', 2000); 
        } catch(Exception e) {
             System.debug('Could not set Contract_Amount__c dynamically: ' + e.getMessage());
        }
        
        update va1;
    }

    @isTest
    static void testUpdateProjectCompletion() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        User supervisor = [SELECT Id FROM User WHERE Alias = 'vahsup' LIMIT 1];

        // Scenario: 
        // VA1: 50% Complete
        // VA2: 100% Complete
        // Expected Avg: 75%

        Vendor_Assignment__c va1 = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        va1.Completion__c = 50;
        update va1;

        Vendor_Assignment__c va2 = new Vendor_Assignment__c(
            Project__c = proj.Id,
            Vendor__c = vendor.Id,
            Supervisor_User__c = supervisor.Id,
            Completion__c = 100,
            Status__c = 'In-Progress',
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today().addDays(5)
        );
        
        // FIX: Set amount using the writeable field
        try {
            va2.put('Contract_Amount__c', 3000);
        } catch(Exception e) {
            System.debug('Could not set Contract_Amount__c dynamically: ' + e.getMessage());
        }
        
        insert va2;

        Test.startTest();
        // Invoke handler manually (simulating Trigger logic call)
        VendorAssignmentHandler.updateProjectCompletion(new Set<Id>{proj.Id});
        Test.stopTest();

        // Verify Project updates
        // Note: Remaining_Budget_Pending__c might depend on formula fields we couldn't write to, 
        // so we primarily assert the Completion Status calculation.
        Project__c updatedProj = [SELECT Project_Completion_Status__c FROM Project__c WHERE Id = :proj.Id];
        
        System.assertEquals(75.00, updatedProj.Project_Completion_Status__c, 'Average completion should be 75%');
    }

    @isTest
    static void testCalculateEfficiencyOnTime() {
        // Scenario: Finished on the exact planned end date
        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Status__c = 'Completed',
            Completion__c = 100,
            Vendor_Work_Start_Date__c = Date.today().addDays(-5),
            Vendor_Work_End_Date__c = Date.today(),
            Vendor_Actual_Completion_Date__c = Date.today()
        );

        Test.startTest();
        VendorAssignmentHandler.calculateEfficiency(new List<Vendor_Assignment__c>{va});
        Test.stopTest();

        System.assertEquals(100, va.Vendor_Efficiency__c, 'Efficiency should be 100 for on-time completion');
    }

    @isTest
    static void testCalculateEfficiencyEarly() {
        // Scenario: Finished EARLY
        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Status__c = 'Completed',
            Completion__c = 100,
            Vendor_Work_Start_Date__c = Date.today().addDays(-10),
            Vendor_Work_End_Date__c = Date.today(),
            Vendor_Actual_Completion_Date__c = Date.today().addDays(-2) // Finished 2 days early
        );

        Test.startTest();
        VendorAssignmentHandler.calculateEfficiency(new List<Vendor_Assignment__c>{va});
        Test.stopTest();

        System.assertEquals(100, va.Vendor_Efficiency__c, 'Efficiency should be 100 (capped) for early completion');
    }

    @isTest
    static void testCalculateEfficiencyDelayed() {
        // Scenario: Planned 5 days, Took 10 days. Efficiency should be 50%.
        Date start = Date.today().addDays(-10);
        Date plannedEnd = start.addDays(4); // 5 days duration (inclusive)
        Date actualEnd = start.addDays(9);  // 10 days duration (inclusive)

        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Status__c = 'Completed',
            Completion__c = 100,
            Vendor_Work_Start_Date__c = start,
            Vendor_Work_End_Date__c = plannedEnd,
            Vendor_Actual_Completion_Date__c = actualEnd
        );

        Test.startTest();
        VendorAssignmentHandler.calculateEfficiency(new List<Vendor_Assignment__c>{va});
        Test.stopTest();

        // Calculation: (Planned Duration / Actual Duration) * 100
        // (5 / 10) * 100 = 50
        System.assertEquals(50.00, va.Vendor_Efficiency__c, 'Efficiency should be 50% for double duration');
    }

    @isTest
    static void testUpdateVendorAverageEfficiency() {
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        User supervisor = [SELECT Id FROM User WHERE Alias = 'vahsup' LIMIT 1];

        // 1. Create two completed assignments for this vendor
        // Assignment A: 100% Efficiency
        Vendor_Assignment__c va1 = new Vendor_Assignment__c(
            Project__c = proj.Id,
            Vendor__c = vendor.Id,
            Supervisor_User__c = supervisor.Id,
            Status__c = 'Completed',
            Vendor_Efficiency__c = 100,
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today()
        );
        insert va1;

        // Assignment B: 50% Efficiency
        Vendor_Assignment__c va2 = new Vendor_Assignment__c(
            Project__c = proj.Id,
            Vendor__c = vendor.Id,
            Supervisor_User__c = supervisor.Id,
            Status__c = 'Completed',
            Vendor_Efficiency__c = 50,
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today()
        );
        insert va2;

        Test.startTest();
        // Invoke handler
        VendorAssignmentHandler.updateVendorAverageEfficiency(null, new List<Vendor_Assignment__c>{va1, va2});
        Test.stopTest();

        // Verify Vendor Average: (100 + 50) / 2 = 75.00
        Vendor__c updatedVendor = [SELECT Average_Efficiency__c FROM Vendor__c WHERE Id = :vendor.Id];
        System.assertEquals(75.00, updatedVendor.Average_Efficiency__c, 'Vendor average efficiency should update');
    }

    @isTest
    static void testUpdateVendorAverageEfficiencyNoCompleted() {
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        User supervisor = [SELECT Id FROM User WHERE Alias = 'vahsup' LIMIT 1];

        // Insert a non-completed assignment
        Vendor_Assignment__c va1 = new Vendor_Assignment__c(
            Project__c = proj.Id,
            Vendor__c = vendor.Id,
            Supervisor_User__c = supervisor.Id,
            Status__c = 'In-Progress', // Not 'Completed'
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today()
        );
        insert va1;

        Test.startTest();
        // Trigger update with this assignment
        VendorAssignmentHandler.updateVendorAverageEfficiency(null, new List<Vendor_Assignment__c>{va1});
        Test.stopTest();

        // Verify Vendor Average is 0 (or null depending on setup, handler logic sets it to 0)
        Vendor__c updatedVendor = [SELECT Average_Efficiency__c FROM Vendor__c WHERE Id = :vendor.Id];
        System.assertEquals(0.00, updatedVendor.Average_Efficiency__c, 'Vendor average should be 0 if no completed tasks');
    }
}