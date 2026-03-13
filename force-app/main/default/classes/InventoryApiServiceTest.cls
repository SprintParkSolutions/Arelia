@IsTest
private class InventoryApiServiceTest {

    @TestSetup
    static void setup() {
        // 1. Create Supervisor
        User u = TestDataUtility.createSupervisorUser('invUser');

        // 2. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Inventory Opp', u.Id);
        // CRITICAL: Updated to 'Home' per your requirement
        opp.Type_of_Project__c = 'Home'; 
        opp.Email__c = 'testclient@example.com'; 
        update opp;

        // 3. Create Products using Utility
        
        // Item 1: Matching Room/Category AND Project Type ('Home')
        Interior_Product__c p1 = TestDataUtility.createInteriorProduct('Accent Wall', 'Dining Hall', 'Painting & Wall Finishing', 1500);
        p1.Type_of_Project__c = 'Home';
        update p1;

        // Item 2: Matching Room/Category AND Project Type ('Home')
        Interior_Product__c p2 = TestDataUtility.createInteriorProduct('Textured Paint', 'Dining Hall', 'Painting & Wall Finishing', 300);
        p2.Type_of_Project__c = 'Home';
        update p2;

        // Item 3: Different Room, different Project Type ('Office')
        Interior_Product__c p3 = TestDataUtility.createInteriorProduct('Electrical board set', 'Living Room', 'Electrical & Networking', 2000);
        p3.Type_of_Project__c = 'Office'; // Should be excluded by getCatalogConfig for 'Home' opps
        update p3;

        // Item 4: Different Category, Matching Type ('Home')
        Interior_Product__c p4 = TestDataUtility.createInteriorProduct('Wooden chairs reception', 'Reception', 'Carpentry & Woodwork', 50);
        p4.Type_of_Project__c = 'Home';
        update p4;
    }

    // ==========================================
    // 1. Tests for getCatalogConfig
    // ==========================================

    @IsTest
    static void testGetCatalogConfigSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Map<String, Object> result = InventoryApiService.getCatalogConfig(opp.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'The result map returned from getCatalogConfig should not be null');

        // 1. Validate Rooms List
        // Should find 'Dining Hall' (from p1, p2) and 'Reception' (from p4) which are 'Home'
        List<String> rooms = (List<String>) result.get('rooms'); 
        Assert.isNotNull(rooms, 'The "rooms" list in the config result should not be null');
        Assert.isTrue(rooms.contains('Dining Hall'), 'The room list should contain "Dining Hall" as it matches the project type');
        Assert.isTrue(rooms.contains('Reception'), 'The room list should contain "Reception" as it matches the project type');
        Assert.isFalse(rooms.contains('Living Room'), 'The room list should NOT contain "Living Room" as it belongs to a different project type (Office)');

        // 2. Validate Categories Map
        Map<String, List<String>> catMap = (Map<String, List<String>>) result.get('categoriesByRoom');
        Assert.isNotNull(catMap, 'The "categoriesByRoom" map should not be null');
        
        // Check Dining Hall categories
        Assert.isTrue(catMap.containsKey('Dining Hall'), 'The category map should contain a key for "Dining Hall"');
        List<String> diningCats = catMap.get('Dining Hall');
        Assert.isTrue(diningCats.contains('Painting & Wall Finishing'), 'The Dining Hall categories should contain "Painting & Wall Finishing"');
    }

    @IsTest
    static void testGetCatalogConfigNullId() {
        Test.startTest();
        try {
            InventoryApiService.getCatalogConfig(null);
            Assert.fail('The method should have thrown an Exception for a null Opportunity Id');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'The exception thrown should be of type AuraHandledException');
        }
        Test.stopTest();
    }

    // ==========================================
    // 2. Tests for getOpportunitySummary
    // ==========================================

    @IsTest
    static void testGetOpportunitySummary() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Opportunity result = InventoryApiService.getOpportunitySummary(opp.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'The service should return a valid Opportunity record');
        Assert.areEqual('Home', result.Type_of_Project__c, 'The Opportunity Type_of_Project__c should match the setup data ("Home")');
        Assert.areEqual('testclient@example.com', result.Email__c, 'The Opportunity Email__c should match the setup data');
    }

    // ==========================================
    // 3. Existing Tests for getProducts (Maintained)
    // ==========================================

    @IsTest
    static void testGetProductsSuccess() {
        Test.startTest();
        // Query matches Setup Data (Dining Hall / Painting)
        List<Interior_Product__c> results = InventoryApiService.getProducts('Dining Hall', 'Painting & Wall Finishing');
        Test.stopTest();

        Assert.isNotNull(results, 'The getProducts method should return a list, not null');
        Assert.areEqual(2, results.size(), 'The query should return exactly 2 matching records for Dining Hall/Painting');
        
        // Verify sorting (ORDER BY Name ASC)
        Assert.areEqual('Accent Wall', results[0].Name, 'The first result should be "Accent Wall" (sorted by Name ASC)');
        Assert.areEqual('Textured Paint', results[1].Name, 'The second result should be "Textured Paint" (sorted by Name ASC)');
    }

    @IsTest
    static void testGetProductsNoMatch() {
        Test.startTest();
        List<Interior_Product__c> results = InventoryApiService.getProducts('Kitchen', 'Appliances');
        Test.stopTest();

        Assert.isNotNull(results, 'The method should return an empty list rather than null when no records match');
        Assert.areEqual(0, results.size(), 'The list size should be 0 for non-matching parameters');
    }

    @IsTest
    static void testGetProductsPartialMatch() {
        Test.startTest();
        List<Interior_Product__c> results = InventoryApiService.getProducts('Dining Hall', 'Flooring & Tiling');
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'The list size should be 0 because the category does not match the room in setup data');
    }

    @IsTest
    static void testGetProductsNullParams() {
        Test.startTest();
        List<Interior_Product__c> results = InventoryApiService.getProducts(null, null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'The list size should be 0 when null parameters are passed');
    }
}