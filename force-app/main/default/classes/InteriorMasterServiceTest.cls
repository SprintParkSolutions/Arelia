/**
 * @File Name         : InteriorMasterServiceTest.cls
 * @Description       : Test class for InteriorMasterService.
 *                      Verifies that master data (project types, categories,
 *                      rooms, designs, design levels, and file URLs) is
 *                      returned correctly for active records only.
 *
 * PMD Notes:
 * - seeAllData=false to keep tests isolated.
 * - All test data created in @testSetup to avoid duplication.
 * - No SOQL/DML inside loops.
 */
@IsTest
private class InteriorMasterServiceTest {

    // We'll store the actual picklist values here so we can assert on them later.
    private static String level1;
    private static String level2;

    @TestSetup
    static void setupData() {
        // ---- Read valid picklist values for Design_Level__c ----
        Schema.DescribeFieldResult dfr = Interior_Design__c.Design_Level__c.getDescribe();
        List<Schema.PicklistEntry> entries = dfr.getPicklistValues();

        // Defensive: make sure there is at least one value configured
        if (!entries.isEmpty()) {
            level1 = entries[0].getValue();
            // If there is only one value, use the same for both records
            level2 = (entries.size() > 1) ? entries[1].getValue() : entries[0].getValue();
        } else {
            // In a very unlikely case there are no values, keep them null
            level1 = null;
            level2 = null;
        }

        // ---- Project Types (1 active, 1 inactive) ----
        Interior_Project_Type__c projActive = new Interior_Project_Type__c(
            Name      = '2BHK',
            Active__c = true
        );
        Interior_Project_Type__c projInactive = new Interior_Project_Type__c(
            Name      = '3BHK',
            Active__c = false
        );
        insert new List<Interior_Project_Type__c>{ projActive, projInactive };

        // ---- Categories (1 active linked to active project type, 1 inactive) ----
        Interior_Category__c catActive = new Interior_Category__c(
            Name                     = 'Living Room Category',
            Interior_Project_Type__c = projActive.Id,
            Active__c                = true
        );
        Interior_Category__c catInactive = new Interior_Category__c(
            Name                     = 'Inactive Category',
            Interior_Project_Type__c = projActive.Id,
            Active__c                = false
        );
        insert new List<Interior_Category__c>{ catActive, catInactive };

        // ---- Rooms (1 active linked to active category, 1 inactive) ----
        Interior_Room__c roomActive = new Interior_Room__c(
            Name                 = 'Living Room',
            Interior_Category__c = catActive.Id,
            Active__c            = true
        );
        Interior_Room__c roomInactive = new Interior_Room__c(
            Name                 = 'Inactive Room',
            Interior_Category__c = catActive.Id,
            Active__c            = false
        );
        insert new List<Interior_Room__c>{ roomActive, roomInactive };

        // ---- Designs (1 active with level & base price, 1 inactive) ----
        Interior_Design__c designActive = new Interior_Design__c(
            Name                 = 'Modern Living Design',
            Interior_Category__c = catActive.Id,
            Interior_Room__c     = roomActive.Id,
            Design_Level__c      = level1,      // ✅ Use valid picklist value
            Description__c       = 'Test premium design',
            Active__c            = true
        );
        Interior_Design__c designInactive = new Interior_Design__c(
            Name                 = 'Inactive Design',
            Interior_Category__c = catActive.Id,
            Interior_Room__c     = roomActive.Id,
            Design_Level__c      = level2,      // ✅ Use another valid picklist value
            Description__c       = 'Should not appear',
            Active__c            = false
        );
        insert new List<Interior_Design__c>{ designActive, designInactive };

        // ---- Create a file (ContentVersion) and publish it to the active design ----
        // FirstPublishLocationId auto-creates a ContentDocumentLink to designActive
        ContentVersion cv = new ContentVersion(
            Title                  = 'Design Image',
            PathOnClient           = 'designImage.jpg',
            VersionData            = Blob.valueOf('dummy image data'),
            FirstPublishLocationId = designActive.Id
        );
        insert cv;

        // ⚠️ No need to insert an extra ContentDocumentLink.
        // The FirstPublishLocationId already created one, so if we insert again
        // we get DUPLICATE_VALUE.
    }

    @IsTest
    static void testGetMasterDataReturnsOnlyActiveRecordsAndFileUrl() {
        Test.startTest();
        InteriorMasterService.MasterDataDTO dto = InteriorMasterService.getMasterData();
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');

        // ---- Project Types ----
        System.assertNotEquals(null,dto.projectTypes,'projectTypes list should not be null');
        System.assertEquals(1,dto.projectTypes.size(), 'Only active project types should be returned');
        System.assertEquals('2BHK',dto.projectTypes[0].name, 'Active project type name mismatch');

        // ---- Categories ----
        System.assertNotEquals(null,dto.categories,'categories list should not be null');
        System.assertEquals(1, dto.categories.size(),'Only active categories should be returned');
        System.assertEquals('Living Room Category',dto.categories[0].name,'Active category name mismatch');

        // ---- Rooms ----
        System.assertNotEquals(null, dto.rooms,'rooms list should not be null');
        System.assertEquals(1, dto.rooms.size(), 'Only active rooms should be returned');
        System.assertEquals('Living Room', dto.rooms[0].name,'Active room name mismatch');

        // ---- Designs ----
        System.assertNotEquals(null, dto.designs, 'designs list should not be null');
        System.assertEquals(1,dto.designs.size(),'Only active designs should be returned');

        InteriorMasterService.DesignDTO designDto = dto.designs[0];
        System.assertEquals('Modern Living Design',designDto.name,'Active design name mismatch');

        // Assert design level matches what we used from picklist (if available)
        if (level1 != null) {
            System.assertEquals(level1,designDto.designLevel,'Design level mismatch');
        }

        System.assertNotEquals(null,designDto.imageUrl,'imageUrl should be set for a design with a linked file');
        System.assert(designDto.imageUrl.startsWith('/sfc/servlet.shepherd/version/download/'),
            'imageUrl should start with the version download path');

        // Cross-check that the version Id at the end of the URL matches LatestPublishedVersionId
        Interior_Design__c activeDesign = [SELECT Id FROM Interior_Design__c
            WHERE Active__c = true LIMIT 1];

        ContentDocumentLink link = [SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink WHERE LinkedEntityId = :activeDesign.Id LIMIT 1];

        Id expectedVersionId = link.ContentDocument.LatestPublishedVersionId;
        System.assert(
            designDto.imageUrl.endsWith(String.valueOf(expectedVersionId)),
            'imageUrl should end with the LatestPublishedVersionId'
        );

        // ---- Design Levels ----
        System.assertNotEquals(null,dto.designLevels,'designLevels should not be null');
        if (level1 != null) {
            System.assert(dto.designLevels.contains(level1),
                'designLevels should contain the level from active design record');
        }
    }
}