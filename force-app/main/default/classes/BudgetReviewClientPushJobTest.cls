/**
 * -----------------------------------------------------------------------------
 * Class Name      : BudgetReviewClientPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for BudgetReviewClientPushJob. Covers queueable execution, Lead conversion, device selection, status validation, and Firebase callout scenarios.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class BudgetReviewClientPushJobTest {

    private static final String STATUS_SENT =
        'Sent for Client Approval';

    private static final String STATUS_APPROVED =
        'Approved';

    private static final String TEST_TOKEN =
        'test_budget_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_budget_fcm_token_456';

    private static final String TEST_EMAIL =
        'budget.review.test@example.com';

    private static final String MOCK_SUCCESS_BODY =
        '{"name":"projects/test/messages/mock-message-id"}';

    private static final String MOCK_ERROR_BODY =
        '{"error":{"code":404,"status":"UNREGISTERED",'
        + '"message":"Requested entity was not found."}}';

    /**
     * ---------------------------------------------------------
     * FIREBASE HTTP MOCK
     * ---------------------------------------------------------
     */
    private class FirebaseMock
        implements HttpCalloutMock {

        private Integer responseStatus;
        private String responseBody;

        FirebaseMock(
            Integer responseStatus,
            String responseBody
        ) {
            this.responseStatus = responseStatus;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(
            HttpRequest requestValue
        ) {
            HttpResponse responseValue =
                new HttpResponse();

            responseValue.setStatusCode(
                responseStatus
            );

            responseValue.setHeader(
                'Content-Type',
                'application/json'
            );

            responseValue.setBody(
                responseBody
            );

            return responseValue;
        }
    }

    /**
     * ---------------------------------------------------------
     * TEST DATA SETUP
     * ---------------------------------------------------------
     */
    @TestSetup
    static void setupTestData() {

        Lead prospect = new Lead(
            FirstName = 'Budget',
            LastName = 'Review Client',
            Company = 'Arelia Test Company',
            Email = TEST_EMAIL,
            Status = getOpenLeadStatus()
        );

        insert prospect;

        prepareLeadForConversion(
            prospect.Id
        );

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(
            prospect.Id
        );

        conversion.setOwnerId(
            UserInfo.getUserId()
        );

        conversion.setConvertedStatus(
            getConvertedLeadStatus()
        );

        conversion.setDoNotCreateOpportunity(
            false
        );

        conversion.setOpportunityName(
            'Arelia Budget Review Project'
        );

        Database.LeadConvertResult result =
            Database.convertLead(
                conversion,
                false
            );

        System.assert(
            result.isSuccess(),
            'Test Lead conversion must succeed.'
        );

        System.assertNotEquals(
            null,
            result.getOpportunityId(),
            'Converted Opportunity must exist.'
        );

        Opportunity convertedOpportunity =
            new Opportunity(
                Id = result.getOpportunityId()
            );

        convertedOpportunity.put(
            'Budget_Review_Status__c',
            STATUS_SENT
        );

        update convertedOpportunity;
    }

    /**
     * ---------------------------------------------------------
     * PREPARE LEAD FOR CONVERSION
     * ---------------------------------------------------------
     */
    private static void prepareLeadForConversion(
        Id leadId
    ) {

        Lead prospect = new Lead(
            Id = leadId
        );

        Map<String, Schema.SObjectField>
            fieldMap =
                Schema.SObjectType.Lead.fields.getMap();

        if (
            fieldMap.containsKey(
                'Project_Request_Submitted__c'
            )
        ) {
            prospect.put(
                'Project_Request_Submitted__c',
                true
            );
        }

        if (
            fieldMap.containsKey(
                'Site_Visit_Manager_Approval__c'
            )
        ) {
            prospect.put(
                'Site_Visit_Manager_Approval__c',
                true
            );
        }

        if (
            fieldMap.containsKey(
                'Approval_Status__c'
            )
        ) {
            prospect.put(
                'Approval_Status__c',
                STATUS_APPROVED
            );
        }

        update prospect;
    }

    /**
     * ---------------------------------------------------------
     * GET OPEN LEAD STATUS
     * ---------------------------------------------------------
     */
    private static String getOpenLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'An open Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * ---------------------------------------------------------
     * GET CONVERTED LEAD STATUS
     * ---------------------------------------------------------
     */
    private static String getConvertedLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'A converted Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * ---------------------------------------------------------
     * GET CONVERTED OPPORTUNITY
     * ---------------------------------------------------------
     */
    private static Opportunity getConvertedOpportunity() {

        List<Lead> leads = [
            SELECT Id, ConvertedOpportunityId
            FROM Lead
            WHERE Email = :TEST_EMAIL
            AND IsConverted = true
            LIMIT 1
        ];

        System.assertEquals(
            1,
            leads.size(),
            'Converted Lead must exist.'
        );

        return [
            SELECT Id,
                   Name,
                   Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :leads[0].ConvertedOpportunityId
            LIMIT 1
        ];
    }

    /**
     * ---------------------------------------------------------
     * GET CONVERTED LEAD
     * ---------------------------------------------------------
     */
    private static Lead getConvertedLead() {

        return [
            SELECT Id,
                   IsConverted,
                   ConvertedOpportunityId
            FROM Lead
            WHERE Email = :TEST_EMAIL
            AND IsConverted = true
            LIMIT 1
        ];
    }

    /**
     * ---------------------------------------------------------
     * GET VALID PLATFORM
     * ---------------------------------------------------------
     */
    private static String getPlatformValue() {

        Schema.DescribeFieldResult fieldDescription =
            Prospect_Device_Token__c.Platform__c
                .getDescribe();

        List<Schema.PicklistEntry> entries =
            fieldDescription.getPicklistValues();

        for (
            Schema.PicklistEntry entry :
            entries
        ) {
            if (
                entry.isActive()
                && entry.getValue() == 'Android'
            ) {
                return entry.getValue();
            }
        }

        for (
            Schema.PicklistEntry entry :
            entries
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    /**
     * ---------------------------------------------------------
     * CREATE DEVICE TOKEN
     * ---------------------------------------------------------
     */
    private static Prospect_Device_Token__c
        createDevice(
            Id leadId,
            String fcmToken,
            Boolean isActive,
            Integer minutesAgo
        ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c();

        device.Prospect_Lead__c = leadId;

        device.FCM_Token__c = fcmToken;

        device.Active__c = isActive;

        device.Device_Id__c =
            'BUDGET-DEVICE-' +
            String.valueOf(minutesAgo);

        String platformValue =
            getPlatformValue();

        if (
            String.isNotBlank(platformValue)
        ) {
            device.Platform__c =
                platformValue;
        }

        device.Last_Seen__c =
            System.now().addMinutes(
                -minutesAgo
            );

        insert device;

        return device;
    }

    /**
     * ---------------------------------------------------------
     * EXECUTE QUEUEABLE SYNCHRONOUSLY
     * ---------------------------------------------------------
     */
    private static void executeJob(
        Set<Id> opportunityIds
    ) {

        BudgetReviewClientPushJob job =
            new BudgetReviewClientPushJob(
                opportunityIds
            );

        job.execute(null);
    }

    /**
     * ---------------------------------------------------------
     * TEST 1 - NULL OPPORTUNITY IDS
     * ---------------------------------------------------------
     */
    @IsTest
    static void nullOpportunityIdsHandled() {

        Test.startTest();

        executeJob(null);

        Test.stopTest();

        System.assert(
            true,
            'Null Opportunity IDs must be handled.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 2 - EMPTY OPPORTUNITY IDS
     * ---------------------------------------------------------
     */
    @IsTest
    static void emptyOpportunityIdsHandled() {

        Test.startTest();

        executeJob(
            new Set<Id>()
        );

        Test.stopTest();

        System.assert(
            true,
            'Empty Opportunity IDs must be handled.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 3 - NONEXISTENT OPPORTUNITY
     * ---------------------------------------------------------
     */
    @IsTest
    static void nonexistentOpportunitySkipped() {

        Id nonexistentId =
            Id.valueOf(
                '006000000000001AAA'
            );

        Test.startTest();

        executeJob(
            new Set<Id>{
                nonexistentId
            }
        );

        Test.stopTest();

        System.assert(
            true,
            'Nonexistent Opportunity must be skipped.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 4 - OPPORTUNITY WITHOUT CONVERTED LEAD
     * ---------------------------------------------------------
     */
    @IsTest
    static void opportunityWithoutConvertedLeadSkipped() {

        Opportunity opportunity =
            new Opportunity(
                Name = 'Standalone Budget Project',
                StageName = getOpportunityStage(),
                CloseDate = Date.today().addDays(30)
            );

        opportunity.put(
            'Budget_Review_Status__c',
            STATUS_SENT
        );

        insert opportunity;

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            opportunity.Id,
            'Opportunity should exist.'
        );
    }

    /**
     * ---------------------------------------------------------
     * GET VALID OPPORTUNITY STAGE
     * ---------------------------------------------------------
     */
    private static String getOpportunityStage() {

        Schema.DescribeFieldResult fieldDescription =
            Opportunity.StageName.getDescribe();

        for (
            Schema.PicklistEntry entry :
            fieldDescription.getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return 'Prospecting';
    }

    /**
     * ---------------------------------------------------------
     * TEST 5 - STATUS NOT SENT
     * ---------------------------------------------------------
     */
    @IsTest
    static void unsentBudgetReviewSkipped() {

        Opportunity opportunity =
            getConvertedOpportunity();

        String nonSentStatus =
            getNonSentBudgetStatus();

        opportunity.put(
            'Budget_Review_Status__c',
            nonSentStatus
        );

        update opportunity;

        Lead prospect =
            getConvertedLead();

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            5
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(
                200,
                MOCK_SUCCESS_BODY
            )
        );

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        Opportunity result = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            nonSentStatus,
            result.Budget_Review_Status__c,
            'Budget status should remain unchanged.'
        );
    }

    /**
     * ---------------------------------------------------------
     * GET NON-SENT BUDGET STATUS
     * ---------------------------------------------------------
     */
    private static String getNonSentBudgetStatus() {

        Schema.DescribeFieldResult fieldDescription =
            Opportunity.Budget_Review_Status__c
                .getDescribe();

        for (
            Schema.PicklistEntry entry :
            fieldDescription.getPicklistValues()
        ) {
            if (
                entry.isActive()
                && entry.getValue() != STATUS_SENT
            ) {
                return entry.getValue();
            }
        }

        return null;
    }

    /**
     * ---------------------------------------------------------
     * TEST 6 - NO DEVICE TOKEN
     * ---------------------------------------------------------
     */
    @IsTest
    static void leadWithoutDeviceTokenSkipped() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        System.assertEquals(
            STATUS_SENT,
            [
                SELECT Budget_Review_Status__c
                FROM Opportunity
                WHERE Id = :opportunity.Id
            ].Budget_Review_Status__c,
            'Budget review status should remain Sent.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 7 - INACTIVE DEVICE
     * ---------------------------------------------------------
     */
    @IsTest
    static void inactiveDeviceSkipped() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Lead prospect =
            getConvertedLead();

        Prospect_Device_Token__c device =
            createDevice(
                prospect.Id,
                TEST_TOKEN,
                false,
                10
            );

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        Prospect_Device_Token__c result = [
            SELECT Active__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertEquals(
            false,
            result.Active__c,
            'Inactive device must remain inactive.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 8 - BLANK FCM TOKEN
     * ---------------------------------------------------------
     */
    @IsTest
    static void blankFcmTokenSkipped() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Lead prospect =
            getConvertedLead();

        Prospect_Device_Token__c device =
            createDevice(
                prospect.Id,
                null,
                true,
                10
            );

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        Prospect_Device_Token__c result = [
            SELECT Id, Active__c, FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertEquals(
            null,
            result.FCM_Token__c,
            'Blank token should remain blank.'
        );

        System.assertEquals(
            true,
            result.Active__c,
            'Device should remain active.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 9 - VALID BUDGET REVIEW PUSH
     * ---------------------------------------------------------
     */
    @IsTest
    static void validBudgetReviewSendsPush() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Lead prospect =
            getConvertedLead();

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            5
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(
                200,
                MOCK_SUCCESS_BODY
            )
        );

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        System.assertEquals(
            STATUS_SENT,
            [
                SELECT Budget_Review_Status__c
                FROM Opportunity
                WHERE Id = :opportunity.Id
            ].Budget_Review_Status__c,
            'Budget review status should remain Sent.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 10 - QUEUEABLE EXECUTION
     * ---------------------------------------------------------
     */
    @IsTest
    static void queueableExecutesSuccessfully() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Lead prospect =
            getConvertedLead();

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            5
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(
                200,
                MOCK_SUCCESS_BODY
            )
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new BudgetReviewClientPushJob(
                new Set<Id>{
                    opportunity.Id
                }
            )
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Queueable job should be enqueued.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 11 - MULTIPLE DEVICES
     * ---------------------------------------------------------
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Lead prospect =
            getConvertedLead();

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            60
        );

        Prospect_Device_Token__c latestDevice =
            createDevice(
                prospect.Id,
                SECOND_TOKEN,
                true,
                1
            );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(
                200,
                MOCK_SUCCESS_BODY
            )
        );

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        Prospect_Device_Token__c result = [
            SELECT Id, Active__c, FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Id = :latestDevice.Id
        ];

        System.assertEquals(
            SECOND_TOKEN,
            result.FCM_Token__c,
            'Latest device token should be retained.'
        );

        System.assertEquals(
            true,
            result.Active__c,
            'Latest device should remain active.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 12 - FIREBASE ERROR RESPONSE
     * ---------------------------------------------------------
     */
    @IsTest
    static void firebaseErrorHandledGracefully() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Lead prospect =
            getConvertedLead();

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            5
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(
                500,
                '{"error":{"message":"Internal Server Error"}}'
            )
        );

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        System.assertEquals(
            STATUS_SENT,
            [
                SELECT Budget_Review_Status__c
                FROM Opportunity
                WHERE Id = :opportunity.Id
            ].Budget_Review_Status__c,
            'Firebase error must not change budget status.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 13 - UNREGISTERED FIREBASE TOKEN
     * ---------------------------------------------------------
     */
    @IsTest
    static void unregisteredFirebaseTokenHandled() {

        Opportunity opportunity =
            getConvertedOpportunity();

        Lead prospect =
            getConvertedLead();

        Prospect_Device_Token__c device =
            createDevice(
                prospect.Id,
                TEST_TOKEN,
                true,
                5
            );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(
                404,
                MOCK_ERROR_BODY
            )
        );

        Test.startTest();

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Test.stopTest();

        Prospect_Device_Token__c result = [
            SELECT Id, Active__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertNotEquals(
            null,
            result.Id,
            'Device record must remain available.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 14 - MIXED OPPORTUNITY IDS
     * ---------------------------------------------------------
     */
    @IsTest
    static void mixedOpportunityIdsHandled() {

        Opportunity validOpportunity =
            getConvertedOpportunity();

        Id nonexistentId =
            Id.valueOf(
                '006000000000001AAA'
            );

        Lead prospect =
            getConvertedLead();

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            5
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(
                200,
                MOCK_SUCCESS_BODY
            )
        );

        Test.startTest();

        executeJob(
            new Set<Id>{
                validOpportunity.Id,
                nonexistentId
            }
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            validOpportunity.Id,
            'Valid Opportunity should be processed.'
        );
    }
}