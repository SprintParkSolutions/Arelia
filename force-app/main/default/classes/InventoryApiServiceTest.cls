@IsTest
private class InventoryApiServiceTest {
    private static final String SUPERVISOR_ALIAS = 'invUser';
    private static final String OPPORTUNITY_NAME = 'Inventory Opp';
    private static final String FALLBACK_OPPORTUNITY_NAME = 'Fallback Inventory Opp';
    private static final String CLIENT_EMAIL = 'testclient@example.com';

    private static final String PROJECT_TYPE_HOME = 'Home';
    private static final String PROJECT_TYPE_OFFICE = 'Office';

    private static final String ROOM_DINING_HALL = 'Dining Hall';
    private static final String ROOM_RECEPTION = 'Reception';
    private static final String ROOM_LIVING_ROOM = 'Living Room';
    private static final String ROOM_KITCHEN = 'Kitchen';

    private static final String CATEGORY_PAINTING = 'Painting & Wall Finishing';
    private static final String CATEGORY_ELECTRICAL = 'Electrical & Networking';
    private static final String CATEGORY_CARPENTRY = 'Carpentry & Woodwork';
    private static final String CATEGORY_APPLIANCES = 'Appliances';
    private static final String CATEGORY_FLOORING = 'Flooring & Tiling';

    private static final String PRODUCT_ACCENT_WALL = 'Accent Wall';
    private static final String PRODUCT_TEXTURED_PAINT = 'Textured Paint';
    private static final String PRODUCT_ELECTRICAL_BOARD = 'Electrical board set';
    private static final String PRODUCT_WOODEN_CHAIRS = 'Wooden chairs reception';
    private static final String PRODUCT_INCOMPLETE_CONFIG = 'Incomplete Config Product';

    @TestSetup
    static void setupTestData() {
        User supervisorUser = TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);

        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            OPPORTUNITY_NAME,
            supervisorUser.Id
        );
        opportunityRecord.Type_of_Project__c = PROJECT_TYPE_HOME;
        opportunityRecord.Email__c = CLIENT_EMAIL;
        update opportunityRecord;

        Opportunity fallbackOpportunity = TestDataUtility.createOpportunity(
            FALLBACK_OPPORTUNITY_NAME,
            supervisorUser.Id
        );
        fallbackOpportunity.Email__c = CLIENT_EMAIL;
        update fallbackOpportunity;

        Interior_Product__c accentWall = TestDataUtility.createInteriorProduct(
            PRODUCT_ACCENT_WALL,
            ROOM_DINING_HALL,
            CATEGORY_PAINTING,
            1500
        );
        accentWall.Type_of_Project__c = PROJECT_TYPE_HOME;

        Interior_Product__c texturedPaint = TestDataUtility.createInteriorProduct(
            PRODUCT_TEXTURED_PAINT,
            ROOM_DINING_HALL,
            CATEGORY_PAINTING,
            300
        );
        texturedPaint.Type_of_Project__c = PROJECT_TYPE_HOME;

        Interior_Product__c electricalBoard = TestDataUtility.createInteriorProduct(
            PRODUCT_ELECTRICAL_BOARD,
            ROOM_LIVING_ROOM,
            CATEGORY_ELECTRICAL,
            2000
        );
        electricalBoard.Type_of_Project__c = PROJECT_TYPE_OFFICE;

        Interior_Product__c woodenChairs = TestDataUtility.createInteriorProduct(
            PRODUCT_WOODEN_CHAIRS,
            ROOM_RECEPTION,
            CATEGORY_CARPENTRY,
            50
        );
        woodenChairs.Type_of_Project__c = PROJECT_TYPE_HOME;

        update new List<Interior_Product__c>{
            accentWall,
            texturedPaint,
            electricalBoard,
            woodenChairs
        };
    }

    @IsTest
    static void testGetCatalogConfigSuccess() {
        Opportunity opportunityRecord = getOpportunityByName(OPPORTUNITY_NAME);

        Test.startTest();
        Map<String, Object> result = InventoryApiService.getCatalogConfig(opportunityRecord.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Catalog config result should not be null.');

        assertCatalogRooms(result);
        assertCatalogCategories(result);
    }

    @IsTest
    static void testGetCatalogConfigSkipsIncompleteProductConfiguration() {
        createIncompleteProductForCatalogCoverage();

        Opportunity opportunityRecord = getOpportunityByName(OPPORTUNITY_NAME);

        Test.startTest();
        Map<String, Object> result = InventoryApiService.getCatalogConfig(opportunityRecord.Id);
        Test.stopTest();

        List<String> rooms = (List<String>) result.get('rooms');

        Assert.isNotNull(result, 'Catalog config result should not be null.');
        Assert.isNotNull(rooms, 'Rooms list should not be null.');
        Assert.isFalse(
            rooms.contains(null),
            'Rooms list should not contain null values from incomplete products.'
        );
        Assert.isTrue(
            rooms.contains(ROOM_DINING_HALL),
            'Valid room data should still be returned.'
        );
    }

    @IsTest
    static void testGetCatalogConfigWithFallbackProjectType() {
        Opportunity fallbackOpportunity = getOpportunityByName(FALLBACK_OPPORTUNITY_NAME);

        Test.startTest();
        Map<String, Object> result = InventoryApiService.getCatalogConfig(fallbackOpportunity.Id);
        Test.stopTest();

        List<String> rooms = (List<String>) result.get('rooms');
        Map<String, List<String>> categoriesByRoom =
            (Map<String, List<String>>) result.get('categoriesByRoom');

        Assert.isNotNull(result, 'Catalog config should return a result map.');
        Assert.isNotNull(rooms, 'Rooms list should not be null.');
        Assert.isNotNull(categoriesByRoom, 'Categories map should not be null.');
    }

    @IsTest
    static void testGetCatalogConfigWithNullOpportunityId() {
        Test.startTest();

        try {
            InventoryApiService.getCatalogConfig(null);
            Assert.fail('Expected AuraHandledException when Opportunity Id is null.');
        } catch (AuraHandledException exceptionRecord) {
            Assert.isNotNull(
                exceptionRecord.getMessage(),
                'AuraHandledException should be thrown for null Opportunity Id.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void testGetOpportunitySummarySuccess() {
        Opportunity opportunityRecord = getOpportunityByName(OPPORTUNITY_NAME);

        Test.startTest();
        Opportunity result = InventoryApiService.getOpportunitySummary(opportunityRecord.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Opportunity summary should not be null.');
        Assert.areEqual(
            PROJECT_TYPE_HOME,
            result.Type_of_Project__c,
            'Opportunity Type_of_Project__c should match the setup data.'
        );
        Assert.areEqual(
            CLIENT_EMAIL,
            result.Email__c,
            'Opportunity Email__c should match the setup data.'
        );
    }

    @IsTest
    static void testGetOpportunitySummaryWithMissingOpportunity() {
        Opportunity temporaryOpportunity = TestDataUtility.createOpportunity(
            'Deleted Inventory Opp',
            UserInfo.getUserId()
        );
        Id deletedOpportunityId = temporaryOpportunity.Id;
        delete temporaryOpportunity;

        Test.startTest();

        try {
            InventoryApiService.getOpportunitySummary(deletedOpportunityId);
            Assert.fail('Expected QueryException when Opportunity record is not found.');
        } catch (QueryException exceptionRecord) {
            Assert.isTrue(
                exceptionRecord.getMessage().contains('List has no rows'),
                'Expected no-row QueryException for deleted Opportunity.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void testGetProductsSuccess() {
        Test.startTest();
        Object productResults = InventoryApiService.getProducts(
            ROOM_DINING_HALL,
            CATEGORY_PAINTING
        );
        Test.stopTest();

        List<Object> rows = getProductResultRows(productResults);

        Assert.isNotNull(productResults, 'Product result should not be null.');
        Assert.areEqual(
            2,
            rows.size(),
            'Expected exactly two products for Dining Hall and Painting category.'
        );
        Assert.isTrue(
            JSON.serialize(productResults).contains(PRODUCT_ACCENT_WALL),
            'Product result should contain Accent Wall.'
        );
        Assert.isTrue(
            JSON.serialize(productResults).contains(PRODUCT_TEXTURED_PAINT),
            'Product result should contain Textured Paint.'
        );
    }

    @IsTest
    static void testGetProductsWithNoMatchingData() {
        Test.startTest();
        Object productResults = InventoryApiService.getProducts(
            ROOM_KITCHEN,
            CATEGORY_APPLIANCES
        );
        Test.stopTest();

        List<Object> rows = getProductResultRows(productResults);

        Assert.isNotNull(productResults, 'Product result should not be null.');
        Assert.areEqual(
            0,
            rows.size(),
            'Expected empty product list for non-matching room and category.'
        );
    }

    @IsTest
    static void testGetProductsWithPartialMatch() {
        Test.startTest();
        Object productResults = InventoryApiService.getProducts(
            ROOM_DINING_HALL,
            CATEGORY_FLOORING
        );
        Test.stopTest();

        List<Object> rows = getProductResultRows(productResults);

        Assert.isNotNull(productResults, 'Product result should not be null.');
        Assert.areEqual(
            0,
            rows.size(),
            'Expected empty product list when room matches but category does not match.'
        );
    }

    @IsTest
    static void testGetProductsWithNullRoomType() {
        Test.startTest();
        Object productResults = InventoryApiService.getProducts(
            null,
            CATEGORY_PAINTING
        );
        Test.stopTest();

        List<Object> rows = getProductResultRows(productResults);

        Assert.isNotNull(productResults, 'Product result should not be null.');
        Assert.areEqual(
            0,
            rows.size(),
            'Expected empty product list when room type is null.'
        );
    }

    @IsTest
    static void testGetProductsWithNullCategory() {
        Test.startTest();
        Object productResults = InventoryApiService.getProducts(
            ROOM_DINING_HALL,
            null
        );
        Test.stopTest();

        List<Object> rows = getProductResultRows(productResults);

        Assert.isNotNull(productResults, 'Product result should not be null.');
        Assert.areEqual(
            0,
            rows.size(),
            'Expected empty product list when category is null.'
        );
    }

    @IsTest
    static void testGetProductsWithBothNullValues() {
        Test.startTest();
        Object productResults = InventoryApiService.getProducts(null, null);
        Test.stopTest();

        List<Object> rows = getProductResultRows(productResults);

        Assert.isNotNull(productResults, 'Product result should not be null.');
        Assert.areEqual(
            0,
            rows.size(),
            'Expected empty product list when both parameters are null.'
        );
    }

    @IsTest
    static void testGetProductsWithBlankStringValues() {
        Test.startTest();
        Object productResults = InventoryApiService.getProducts('', '');
        Test.stopTest();

        List<Object> rows = getProductResultRows(productResults);

        Assert.isNotNull(productResults, 'Product result should not be null.');
        Assert.areEqual(
            0,
            rows.size(),
            'Expected empty product list when both parameters are blank strings.'
        );
    }

    private static Opportunity getOpportunityByName(String opportunityName) {
        return [
            SELECT Id, Type_of_Project__c, Email__c
            FROM Opportunity
            WHERE Name = :opportunityName
            LIMIT 1
        ];
    }

    private static void createIncompleteProductForCatalogCoverage() {
        Interior_Product__c productRecord = TestDataUtility.createInteriorProduct(
            PRODUCT_INCOMPLETE_CONFIG,
            ROOM_DINING_HALL,
            CATEGORY_PAINTING,
            75
        );

        productRecord.Room_Type__c = null;
        productRecord.Type_of_Project__c = PROJECT_TYPE_HOME;
        update productRecord;
    }

    private static void assertCatalogRooms(Map<String, Object> result) {
        List<String> rooms = (List<String>) result.get('rooms');

        Assert.isNotNull(rooms, 'Rooms list should not be null.');
        Assert.isTrue(
            rooms.contains(ROOM_DINING_HALL),
            'Rooms should contain Dining Hall for Home project type.'
        );
        Assert.isTrue(
            rooms.contains(ROOM_RECEPTION),
            'Rooms should contain Reception for Home project type.'
        );
        Assert.isFalse(
            rooms.contains(ROOM_LIVING_ROOM),
            'Rooms should not contain Living Room because it belongs to Office project type.'
        );
    }

    private static void assertCatalogCategories(Map<String, Object> result) {
        Map<String, List<String>> categoriesByRoom =
            (Map<String, List<String>>) result.get('categoriesByRoom');

        Assert.isNotNull(categoriesByRoom, 'Categories by room map should not be null.');
        Assert.isTrue(
            categoriesByRoom.containsKey(ROOM_DINING_HALL),
            'Categories map should contain Dining Hall.'
        );
        Assert.isTrue(
            categoriesByRoom.get(ROOM_DINING_HALL).contains(CATEGORY_PAINTING),
            'Dining Hall should contain Painting & Wall Finishing category.'
        );
        Assert.isTrue(
            categoriesByRoom.containsKey(ROOM_RECEPTION),
            'Categories map should contain Reception.'
        );
        Assert.isTrue(
            categoriesByRoom.get(ROOM_RECEPTION).contains(CATEGORY_CARPENTRY),
            'Reception should contain Carpentry & Woodwork category.'
        );
        Assert.isFalse(
            categoriesByRoom.containsKey(ROOM_LIVING_ROOM),
            'Categories map should not contain Living Room because it belongs to Office project type.'
        );
    }

    private static List<Object> getProductResultRows(Object productResults) {
        return (List<Object>) JSON.deserializeUntyped(JSON.serialize(productResults));
    }
}