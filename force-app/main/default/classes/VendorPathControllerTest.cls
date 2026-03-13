@isTest
public class VendorPathControllerTest {

    @testSetup
    static void setup() {
        // 1. Create Prerequisites using Utility
        Account acc = TestDataUtility.createAccount('Path Account');
        
        Contact con = TestDataUtility.createContact('Path Contact', 'path@test.com', 'password123');
        con.AccountId = acc.Id;
        update con;

        // 2. Create Project (Required for Vendor Assignment)
        Project__c proj = TestDataUtility.createProject('Test Project Path', 5000, con.Id);

        // 3. Create Base Vendor Assignment
        TestDataUtility.createVendorAssignment(proj.Id, 100);
    }

    @isTest
    static void testStatusCompleted() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        va.Status__c = 'Completed';
        update va;

        Test.startTest();
        String result = VendorPathController.getPathStatus(va.Id);
        Test.stopTest();

        Assert.areEqual('Vendor Work Completed', result, 'Should return Vendor Work Completed step');
    }

    @isTest
    static void testStatusAbscond() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        va.Status__c = 'Abscond';
        update va;

        Test.startTest();
        String result = VendorPathController.getPathStatus(va.Id);
        Test.stopTest();

        Assert.areEqual('Abscond', result, 'Should return Abscond step');
    }

    @isTest
    static void testStatusInProgress() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        va.Status__c = 'In-Progress'; 
        update va;

        Test.startTest();
        String result = VendorPathController.getPathStatus(va.Id);
        Test.stopTest();

        Assert.areEqual('Ongoing Tasks', result, 'Should return Ongoing Tasks step');
    }

    @isTest
    static void testStatusInitiated() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        va.Status__c = 'Initiated';
        // Ensure dates don't override status logic if automation exists
        va.Vendor_Work_Start_Date__c = Date.today().addDays(1); 
        update va;

        Test.startTest();
        String result = VendorPathController.getPathStatus(va.Id);
        Test.stopTest();

        Assert.areEqual('Vendor Work Started', result, 'Should return Vendor Work Started step');
    }

    @isTest
    static void testStatusDefault() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        
        // FIX: Dynamically find a valid status that triggers the "Default" path
        // (i.e., NOT Completed, Abscond, In Progress, or Initiated)
        String targetStatus = null;
        Set<String> specialStatuses = new Set<String>{
            'Completed', 'Abscond', 'In Progress', 'In-Progress', 'Initiated'
        };
        
        Schema.DescribeFieldResult fieldResult = Vendor_Assignment__c.Status__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        
        for(Schema.PicklistEntry f : ple) {
            if(f.isActive() && !specialStatuses.contains(f.getValue())) {
                targetStatus = f.getValue();
                break;
            }
        }

        // If we found a valid "other" status, use it. Otherwise, we rely on null or skip if restricted.
        if (targetStatus != null) {
            va.Status__c = targetStatus;
            
            // Move dates to future to prevent automation from reverting status to In-Progress
            va.Vendor_Work_Start_Date__c = Date.today().addDays(5);
            va.Vendor_Work_End_Date__c = Date.today().addDays(10);
            
            update va;

            Test.startTest();
            String result = VendorPathController.getPathStatus(va.Id);
            Test.stopTest();

            // Logic: Default fallback -> Returns 'Vendor Assigned'
            Assert.areEqual('Vendor Assigned', result, 'Should return default step for status: ' + targetStatus);
        } else {
            System.debug('Skipping testStatusDefault verification: No valid non-special status found in org config.');
        }
    }

    @isTest
    static void testInvalidInputs() {
        Test.startTest();
        
        String resNull = VendorPathController.getPathStatus(null);
        Assert.isNull(resNull, 'Should return null for null ID');

        Account acc = [SELECT Id FROM Account LIMIT 1];
        String resWrongObj = VendorPathController.getPathStatus(acc.Id);
        Assert.isNull(resWrongObj, 'Should return null for wrong object ID');

        Test.stopTest();
    }
}