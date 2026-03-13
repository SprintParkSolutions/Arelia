@isTest
public class VendorOpportunityTriggerDispatcherTest {

    @testSetup
    static void setupData() {
        // 1. Create Supervisor using Utility
        User supervisor = TestDataUtility.createSupervisorUser('SupDisp');

        // 2. Create Opportunity using Utility
        Opportunity opp = TestDataUtility.createOpportunity('Dispatcher Opp', supervisor.Id);
        
        // FIX: Satisfy Validation Rule ("You cannot create a Vendor Opportunity until...")
        // Set these flags to TRUE so subsequent tests can insert Vendor Opportunities.
        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        
        // Ensure flag starts as false for testing logic
        opp.All_Vendors_Agreement_Completed__c = false;
        update opp;

        // 3. Create Vendor using Utility
        TestDataUtility.createVendor('Disp Vendor', 'Plumbing & Sanitary', 'disp@test.com');
    }

    @isTest
    static void testInsertDispatch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        Test.startTest();
        // 1. Insert a VO that is explicitly SIGNED
        // This should fire Trigger -> Dispatcher -> Service -> Opp Update
        
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id,
            Vendor__c = vendor.Id,
            Vendor_Agreement_Signed__c = true
        );
        insert vo;
        Test.stopTest();

        // Verify: The dispatcher successfully passed the ID to the service
        Opportunity result = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, result.All_Vendors_Agreement_Completed__c, 'Dispatcher should invoke service on Insert');
    }

    @isTest
    static void testUpdateDispatch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        // 1. Insert VO as NOT Signed
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id,
            Vendor__c = vendor.Id,
            Vendor_Agreement_Signed__c = false
        );
        insert vo;

        // Verify initial state
        Opportunity initial = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, initial.All_Vendors_Agreement_Completed__c, 'Initial state should be false');

        Test.startTest();
        // 2. Update VO to SIGNED
        vo.Vendor_Agreement_Signed__c = true;
        update vo;
        Test.stopTest();

        // Verify: Dispatcher handled the update trigger context
        Opportunity result = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, result.All_Vendors_Agreement_Completed__c, 'Dispatcher should invoke service on Update');
    }

    @isTest
    static void testDeleteDispatch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        // 1. Create two VOs: One Signed, One Unsigned
        // Result: Opp should be False (1/2 signed)
        Vendor_Opportunity__c vSigned = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id, Vendor__c = vendor.Id, Vendor_Agreement_Signed__c = true
        );
        Vendor_Opportunity__c vUnsigned = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id, Vendor__c = vendor.Id, Vendor_Agreement_Signed__c = false
        );
        insert new List<Vendor_Opportunity__c>{vSigned, vUnsigned};

        Test.startTest();
        // 2. Delete the UNSIGNED one
        // Dispatcher should verify Trigger.old contains the record and call service.
        // Service logic: Now 1/1 records are signed -> Flip Opp to True.
        delete vUnsigned;
        Test.stopTest();

        // Verify
        Opportunity result = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, result.All_Vendors_Agreement_Completed__c, 'Dispatcher should invoke service on Delete (Trigger.old)');
    }

    @isTest
    static void testUndeleteDispatch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        // 1. Setup Scenario: 1 Signed, 1 Unsigned
        Vendor_Opportunity__c vSigned = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id, Vendor__c = vendor.Id, Vendor_Agreement_Signed__c = true
        );
        Vendor_Opportunity__c vUnsigned = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id, Vendor__c = vendor.Id, Vendor_Agreement_Signed__c = false
        );
        insert new List<Vendor_Opportunity__c>{vSigned, vUnsigned};
        
        // 2. Delete the unsigned one so Opp becomes TRUE
        delete vUnsigned;
        
        // Verify intermediate state
        Opportunity midResult = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, midResult.All_Vendors_Agreement_Completed__c, 'Intermediate state should be true');

        Test.startTest();
        // 3. Undelete the unsigned one
        // Dispatcher should verify Trigger.new contains the restored record.
        // Service logic: Now 1/2 records signed -> Flip Opp back to FALSE.
        undelete vUnsigned;
        Test.stopTest();

        // Verify
        Opportunity finalResult = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, finalResult.All_Vendors_Agreement_Completed__c, 'Dispatcher should invoke service on Undelete');
    }
}