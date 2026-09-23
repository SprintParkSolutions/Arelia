/**
 * @description Test class for VendorOpportunityAgreementService.
 * Validates agreement recalculation, Opportunity completion updates,
 * no-file-copy behavior, empty input handling, and bulk scenarios.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc')
private class VendorOpportunityAgreementServiceTest {
    private static final String SUPERVISOR_ALIAS = 'SupAgre';
    private static final String OPPORTUNITY_NAME = 'Agreement Opp';
    private static final String NO_VENDOR_OPP_NAME = 'No Vendor Agreement Opp';
    private static final String BULK_OPP_ONE_NAME = 'Bulk Agreement Opp One';
    private static final String BULK_OPP_TWO_NAME = 'Bulk Agreement Opp Two';

    private static final String VENDOR_ONE_NAME = 'Vendor One';
    private static final String VENDOR_TWO_NAME = 'Vendor Two';
    private static final String VENDOR_THREE_NAME = 'Vendor Three';

    private static final String VENDOR_CATEGORY_CARPENTRY =
        'Carpentry & Woodwork';
    private static final String VENDOR_CATEGORY_ELECTRICAL =
        'Electrical & Networking';

    private static final String VENDOR_ONE_EMAIL = 'v1@test.com';
    private static final String VENDOR_TWO_EMAIL = 'v2@test.com';
    private static final String VENDOR_THREE_EMAIL = 'v3@test.com';

    private static final String STATUS_ACTIVE = 'Active';

    @TestSetup
    static void setupData() {
        User supervisor =
            TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);

        Opportunity opportunityRecord =
            TestDataUtility.createOpportunity(
                OPPORTUNITY_NAME,
                supervisor.Id
            );

        opportunityRecord.Client_Agreement_Sent__c = true;
        opportunityRecord.Client_Agreement_Signed__c = true;
        opportunityRecord.All_Vendors_Agreement_Completed__c = false;
        update opportunityRecord;

        Vendor__c vendorOne =
            TestDataUtility.createVendor(
                VENDOR_ONE_NAME,
                VENDOR_CATEGORY_CARPENTRY,
                VENDOR_ONE_EMAIL
            );

        Vendor__c vendorTwo =
            TestDataUtility.createVendor(
                VENDOR_TWO_NAME,
                VENDOR_CATEGORY_ELECTRICAL,
                VENDOR_TWO_EMAIL
            );

        TestDataUtility.createVendor(
            VENDOR_THREE_NAME,
            VENDOR_CATEGORY_CARPENTRY,
            VENDOR_THREE_EMAIL
        );

        Vendor_Opportunity__c vendorOppOne =
            TestDataUtility.createVendorOpportunity(
                opportunityRecord.Id,
                vendorOne.Id,
                STATUS_ACTIVE
            );

        vendorOppOne.Vendor_Agreement_Signed__c = false;

        Vendor_Opportunity__c vendorOppTwo =
            TestDataUtility.createVendorOpportunity(
                opportunityRecord.Id,
                vendorTwo.Id,
                STATUS_ACTIVE
            );

        vendorOppTwo.Vendor_Agreement_Signed__c = false;

        update new List<Vendor_Opportunity__c>{
            vendorOppOne,
            vendorOppTwo
        };

        Assert.isNotNull(
            supervisor.Id,
            'Supervisor user should be created through TestDataUtility.'
        );
    }

    @IsTest
    static void testNullAndEmptyInputReturnSafely() {
        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(null);
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>()
        );
        Test.stopTest();

        Opportunity opportunityRecord =
            getOpportunityByName(OPPORTUNITY_NAME);

        Assert.areEqual(
            false,
            opportunityRecord.All_Vendors_Agreement_Completed__c,
            'Null and empty input should not update Opportunity.'
        );
    }

    @IsTest
    static void testPartialCompletionKeepsOpportunityIncomplete() {
        Opportunity opportunityRecord =
            getOpportunityByName(OPPORTUNITY_NAME);

        Vendor_Opportunity__c vendorOppOne =
            getVendorOpportunityByVendorName(VENDOR_ONE_NAME);

        vendorOppOne.Vendor_Agreement_Signed__c = true;
        update vendorOppOne;

        resetOpportunityVendorCompletionFlag(opportunityRecord.Id);

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity result = getOpportunityById(opportunityRecord.Id);

        Assert.areEqual(
            false,
            result.All_Vendors_Agreement_Completed__c,
            'Opportunity should remain incomplete when only one vendor agreement is signed.'
        );
    }

    @IsTest
    static void testFullCompletionMarksOpportunityCompleteWithoutCopyingFiles() {
        Opportunity opportunityRecord =
            getOpportunityByName(OPPORTUNITY_NAME);

        List<Vendor_Opportunity__c> vendorOpps =
            getVendorOpportunities(opportunityRecord.Id);

        for (Vendor_Opportunity__c vendorOpp : vendorOpps) {
            vendorOpp.Vendor_Agreement_Signed__c = true;
        }

        update vendorOpps;

        resetOpportunityVendorCompletionFlag(opportunityRecord.Id);

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity result = getOpportunityById(opportunityRecord.Id);

        Integer opportunityFileCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :opportunityRecord.Id
        ];

        Assert.areEqual(
            true,
            result.All_Vendors_Agreement_Completed__c,
            'Opportunity should be complete when all vendor agreements are signed.'
        );

        Assert.areEqual(
            0,
            opportunityFileCount,
            'Vendor Opportunity files should not be copied to the parent Opportunity.'
        );
    }

    @IsTest
    static void testReversionToFalseWhenVendorIsUnsigned() {
        Opportunity opportunityRecord =
            getOpportunityByName(OPPORTUNITY_NAME);

        List<Vendor_Opportunity__c> vendorOpps =
            getVendorOpportunities(opportunityRecord.Id);

        for (Vendor_Opportunity__c vendorOpp : vendorOpps) {
            vendorOpp.Vendor_Agreement_Signed__c = true;
        }

        update vendorOpps;

        resetOpportunityVendorCompletionFlag(opportunityRecord.Id);

        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );

        vendorOpps[0].Vendor_Agreement_Signed__c = false;
        update vendorOpps[0];

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity result = getOpportunityById(opportunityRecord.Id);

        Assert.areEqual(
            false,
            result.All_Vendors_Agreement_Completed__c,
            'Opportunity should revert to incomplete when one vendor agreement is unsigned.'
        );
    }

    @IsTest
    static void testNoVendorOpportunitiesKeepsOpportunityIncomplete() {
        Opportunity opportunityRecord =
            createAgreementReadyOpportunity(NO_VENDOR_OPP_NAME);

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity result = getOpportunityById(opportunityRecord.Id);

        Assert.areEqual(
            false,
            result.All_Vendors_Agreement_Completed__c,
            'Opportunity should remain incomplete when it has no Vendor Opportunity records.'
        );
    }

    @IsTest
    static void testNoUpdateNeededWhenCurrentStateAlreadyMatchesTrue() {
        Opportunity opportunityRecord =
            createAgreementReadyOpportunity('Already Complete Opp');

        Vendor__c vendorRecord = getVendorByName(VENDOR_THREE_NAME);

        Vendor_Opportunity__c vendorOpp =
            TestDataUtility.createVendorOpportunity(
                opportunityRecord.Id,
                vendorRecord.Id,
                STATUS_ACTIVE
            );

        vendorOpp.Vendor_Agreement_Signed__c = true;
        update vendorOpp;

        opportunityRecord.All_Vendors_Agreement_Completed__c = true;
        update opportunityRecord;

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity result = getOpportunityById(opportunityRecord.Id);

        Assert.areEqual(
            true,
            result.All_Vendors_Agreement_Completed__c,
            'Opportunity should stay complete when current value already matches desired state.'
        );
    }

    @IsTest
    static void testNoUpdateNeededWhenCurrentStateAlreadyMatchesFalse() {
        Opportunity opportunityRecord =
            createAgreementReadyOpportunity('Already Incomplete Opp');

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity result = getOpportunityById(opportunityRecord.Id);

        Assert.areEqual(
            false,
            result.All_Vendors_Agreement_Completed__c,
            'Opportunity should stay incomplete when no vendor records exist and current state is false.'
        );
    }

    @IsTest
    static void testSingleVendorCompletionMarksOpportunityComplete() {
        Opportunity opportunityRecord =
            createAgreementReadyOpportunity('Single Vendor Completion Opp');

        Vendor__c vendorRecord = getVendorByName(VENDOR_THREE_NAME);

        Vendor_Opportunity__c vendorOpp =
            TestDataUtility.createVendorOpportunity(
                opportunityRecord.Id,
                vendorRecord.Id,
                STATUS_ACTIVE
            );

        vendorOpp.Vendor_Agreement_Signed__c = true;
        update vendorOpp;

        resetOpportunityVendorCompletionFlag(opportunityRecord.Id);

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Opportunity result = getOpportunityById(opportunityRecord.Id);

        Integer opportunityFileCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :opportunityRecord.Id
        ];

        Assert.areEqual(
            true,
            result.All_Vendors_Agreement_Completed__c,
            'Opportunity should be complete when the only vendor agreement is signed.'
        );

        Assert.areEqual(
            0,
            opportunityFileCount,
            'No vendor agreement files should be copied to Opportunity.'
        );
    }

    @IsTest
    static void testBulkOpportunitiesRecalculateCorrectly() {
        Opportunity bulkOppOne =
            createAgreementReadyOpportunity(BULK_OPP_ONE_NAME);

        Opportunity bulkOppTwo =
            createAgreementReadyOpportunity(BULK_OPP_TWO_NAME);

        Vendor__c vendorOne = getVendorByName(VENDOR_ONE_NAME);
        Vendor__c vendorTwo = getVendorByName(VENDOR_TWO_NAME);

        Vendor_Opportunity__c signedVendorOpp =
            TestDataUtility.createVendorOpportunity(
                bulkOppOne.Id,
                vendorOne.Id,
                STATUS_ACTIVE
            );

        signedVendorOpp.Vendor_Agreement_Signed__c = true;

        Vendor_Opportunity__c unsignedVendorOpp =
            TestDataUtility.createVendorOpportunity(
                bulkOppTwo.Id,
                vendorTwo.Id,
                STATUS_ACTIVE
            );

        unsignedVendorOpp.Vendor_Agreement_Signed__c = false;

        update new List<Vendor_Opportunity__c>{
            signedVendorOpp,
            unsignedVendorOpp
        };

        resetOpportunityVendorCompletionFlag(bulkOppOne.Id);
        resetOpportunityVendorCompletionFlag(bulkOppTwo.Id);

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(
            new Set<Id>{ bulkOppOne.Id, bulkOppTwo.Id }
        );
        Test.stopTest();

        Map<Id, Opportunity> results =
            new Map<Id, Opportunity>([
                SELECT Id,
                       All_Vendors_Agreement_Completed__c
                FROM Opportunity
                WHERE Id IN :new Set<Id>{
                    bulkOppOne.Id,
                    bulkOppTwo.Id
                }
            ]);

        Assert.areEqual(
            true,
            results.get(bulkOppOne.Id).All_Vendors_Agreement_Completed__c,
            'Bulk Opportunity One should be complete.'
        );

        Assert.areEqual(
            false,
            results.get(bulkOppTwo.Id).All_Vendors_Agreement_Completed__c,
            'Bulk Opportunity Two should remain incomplete.'
        );
    }

    private static Opportunity createAgreementReadyOpportunity(
        String opportunityName
    ) {
        Opportunity opportunityRecord =
            TestDataUtility.createOpportunity(
                opportunityName,
                getSupervisorUser().Id
            );

        opportunityRecord.Client_Agreement_Sent__c = true;
        opportunityRecord.Client_Agreement_Signed__c = true;
        opportunityRecord.All_Vendors_Agreement_Completed__c = false;
        update opportunityRecord;

        return opportunityRecord;
    }

    private static void resetOpportunityVendorCompletionFlag(
        Id opportunityId
    ) {
        update new Opportunity(
            Id = opportunityId,
            All_Vendors_Agreement_Completed__c = false
        );
    }

    private static User getSupervisorUser() {
        return [
            SELECT Id
            FROM User
            WHERE Alias = :SUPERVISOR_ALIAS
            LIMIT 1
        ];
    }

    private static Opportunity getOpportunityByName(
        String opportunityName
    ) {
        return [
            SELECT Id,
                   All_Vendors_Agreement_Completed__c
            FROM Opportunity
            WHERE Name = :opportunityName
            LIMIT 1
        ];
    }

    private static Opportunity getOpportunityById(
        Id opportunityId
    ) {
        return [
            SELECT Id,
                   All_Vendors_Agreement_Completed__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
    }

    private static Vendor__c getVendorByName(
        String vendorName
    ) {
        return [
            SELECT Id,
                   Name
            FROM Vendor__c
            WHERE Name = :vendorName
            LIMIT 1
        ];
    }

    private static Vendor_Opportunity__c getVendorOpportunityByVendorName(
        String vendorName
    ) {
        return [
            SELECT Id,
                   Vendor_Agreement_Signed__c
            FROM Vendor_Opportunity__c
            WHERE Vendor__r.Name = :vendorName
            LIMIT 1
        ];
    }

    private static List<Vendor_Opportunity__c> getVendorOpportunities(
        Id opportunityId
    ) {
        return [
            SELECT Id,
                   Vendor_Agreement_Signed__c
            FROM Vendor_Opportunity__c
            WHERE Opportunity__c = :opportunityId
        ];
    }
}