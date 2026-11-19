/**
 * -----------------------------------------------------------------------------
 * Class Name      : BudgetReviewManagerApprovedPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for BudgetReviewManagerApprovedPushJob.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class BudgetReviewManagerApprovedPushJobTest {

    private static final String STATUS_MANAGER_APPROVED =
        'Manager Approved';

    private static final String STATUS_SENT =
        'Sent for Client Approval';

    private static final String APPROVAL_APPROVED =
        'Approved';

    private static final String TEST_TOKEN =
        'test_budget_manager_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_budget_manager_fcm_token_456';

    private static final String TEST_EMAIL =
        'budget.manager.test@example.com';

    private static final String TEST_COMPANY =
        'Arelia Budget Test';

    /**
     * Mock Firebase HTTP responses.
     */
    private class FirebaseMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest requestValue) {

            System.assertNotEquals(
                null,
                requestValue,
                'HTTP request should not be null.'
            );

            HttpResponse responseValue = new HttpResponse();

            responseValue.setStatusCode(200);
            responseValue.setHeader(
                'Content-Type',
                'application/json'
            );

            responseValue.setBody(
                '{"name":"projects/test/messages/test123",' +
                '"success":true,' +
                '"access_token":"test_access_token",' +
                '"token_type":"Bearer",' +
                '"expires_in":3600}'
            );

            return responseValue;
        }
    }

    /**
     * Creates a test Lead.
     */
    private static Lead createTestLead(String suffix) {

        Lead prospect = new Lead(
            FirstName = 'Budget',
            LastName = 'Manager' + suffix,
            Company = TEST_COMPANY + suffix,
            Email = suffix + TEST_EMAIL,
            Status = getOpenLeadStatus(),
            OwnerId = UserInfo.getUserId()
        );

        setFieldIfWritable(
            prospect,
            'Project_Request_Submitted__c',
            true
        );

        setFieldIfWritable(
            prospect,
            'Site_Visit_Manager_Approval__c',
            true
        );

        setFieldIfWritable(
            prospect,
            'Approval_Status__c',
            APPROVAL_APPROVED
        );

        insert prospect;

        return prospect;
    }

    /**
     * Returns an available unconverted Lead status.
     */
    private static String getOpenLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'An open Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Returns a valid converted Lead status.
     */
    private static String getConvertedLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'A converted Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Sets an available writable field dynamically.
     */
    private static void setFieldIfWritable(
        SObject recordValue,
        String fieldApiName,
        Object fieldValue
    ) {

        Map<String, Schema.SObjectField> fieldMap =
            recordValue.getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        if (!fieldMap.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescription =
            fieldMap.get(fieldApiName).getDescribe();

        if (fieldDescription.isCreateable()) {
            recordValue.put(fieldApiName, fieldValue);
        }
    }

    /**
     * Converts a Lead and returns its Opportunity.
     */
    private static Opportunity createConvertedOpportunity(
        String suffix,
        String budgetStatus
    ) {

        Lead prospect = createTestLead(suffix);

        Database.LeadConvert conversionRequest =
            new Database.LeadConvert();

        conversionRequest.setLeadId(prospect.Id);

        conversionRequest.setConvertedStatus(
            getConvertedLeadStatus()
        );

        conversionRequest.setDoNotCreateOpportunity(false);

        conversionRequest.setOpportunityName(
            'Budget Review Opportunity ' + suffix
        );

        conversionRequest.setOwnerId(
            UserInfo.getUserId()
        );

        Database.LeadConvertResult conversionResult =
            Database.convertLead(
                conversionRequest,
                false
            );

        System.assert(
            conversionResult.isSuccess(),
            'Lead conversion failed: ' +
            conversionResult.getErrors()
        );

        Id opportunityId =
            conversionResult.getOpportunityId();

        System.assertNotEquals(
            null,
            opportunityId,
            'Converted Opportunity should exist.'
        );

        Opportunity opportunity = [
            SELECT
                Id,
                Name,
                Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        opportunity.Budget_Review_Status__c =
            budgetStatus;

        update opportunity;

        return opportunity;
    }

    /**
     * Creates an Opportunity without Lead conversion.
     */
    private static Opportunity createStandaloneOpportunity(
        String suffix
    ) {

        Opportunity opportunity = new Opportunity(
            Name = 'Standalone Budget ' + suffix,
            StageName = getOpportunityStage(),
            CloseDate = Date.today().addDays(30),
            Budget_Review_Status__c =
                STATUS_MANAGER_APPROVED
        );

        insert opportunity;

        return opportunity;
    }

    /**
     * Returns an active Opportunity stage.
     */
    private static String getOpportunityStage() {

        List<OpportunityStage> stages = [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !stages.isEmpty(),
            'An active Opportunity stage must exist.'
        );

        return stages[0].MasterLabel;
    }

    /**
     * Creates a Prospect device token.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String token,
        Boolean isActive,
        String suffix
    ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c();

        device.Prospect_Lead__c = leadId;
        device.Device_Id__c =
            'budget_manager_device_' + suffix;

        device.FCM_Token__c = token;
        device.Active__c = isActive;
        device.Last_Seen__c = System.now();

        insert device;

        return device;
    }

    /**
     * Returns the converted Lead linked to an Opportunity.
     */
    private static Lead getConvertedLead(
        Id opportunityId
    ) {

        List<Lead> convertedLeads = [
            SELECT
                Id,
                IsConverted,
                ConvertedOpportunityId
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityId
            LIMIT 1
        ];

        System.assertEquals(
            1,
            convertedLeads.size(),
            'Converted Lead should be found.'
        );

        return convertedLeads[0];
    }

    /**
     * Enqueues the Queueable job.
     */
    private static void executeJob(
        Set<Id> opportunityIds
    ) {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock()
        );

        Test.startTest();

        System.enqueueJob(
            new BudgetReviewManagerApprovedPushJob(
                opportunityIds
            )
        );

        Test.stopTest();
    }

    /**
     * Tests null Opportunity IDs.
     */
    @IsTest
    static void nullOpportunityIdsHandled() {

        executeJob(null);

        System.assert(
            true,
            'Null Opportunity IDs handled successfully.'
        );
    }

    /**
     * Tests empty Opportunity IDs.
     */
    @IsTest
    static void emptyOpportunityIdsHandled() {

        executeJob(new Set<Id>());

        System.assert(
            true,
            'Empty Opportunity IDs handled successfully.'
        );
    }

    /**
     * Tests non-existing Opportunity IDs.
     */
    @IsTest
    static void nonexistentOpportunitySkipsProcessing() {

        Id fakeOpportunityId =
            Id.valueOf('006000000000001AAA');

        executeJob(
            new Set<Id>{ fakeOpportunityId }
        );

        System.assert(
            true,
            'Non-existing Opportunity handled successfully.'
        );
    }

    /**
     * Tests Opportunity without converted Lead.
     */
    @IsTest
    static void opportunityWithoutConvertedLeadSkipsPush() {

        Opportunity opportunity =
            createStandaloneOpportunity('NoLead');

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        Opportunity resultValue = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_MANAGER_APPROVED,
            resultValue.Budget_Review_Status__c
        );
    }

    /**
     * Tests non-approved budget status.
     */
    @IsTest
    static void incorrectBudgetStatusSkipsPush() {

        Opportunity opportunity =
            createConvertedOpportunity(
                'WrongStatus',
                STATUS_SENT
            );

        Lead prospect =
            getConvertedLead(opportunity.Id);

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            'WrongStatus'
        );

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        Opportunity resultValue = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_SENT,
            resultValue.Budget_Review_Status__c
        );
    }

    /**
     * Tests approved Opportunity without device.
     */
    @IsTest
    static void leadWithoutDeviceSkipsPush() {

        Opportunity opportunity =
            createConvertedOpportunity(
                'NoDevice',
                STATUS_MANAGER_APPROVED
            );

        Lead prospect =
            getConvertedLead(opportunity.Id);

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        Integer deviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
        ];

        System.assertEquals(
            0,
            deviceCount,
            'No device should exist.'
        );
    }

    /**
     * Tests inactive device token.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Opportunity opportunity =
            createConvertedOpportunity(
                'Inactive',
                STATUS_MANAGER_APPROVED
            );

        Lead prospect =
            getConvertedLead(opportunity.Id);

        Prospect_Device_Token__c device =
            createDevice(
                prospect.Id,
                TEST_TOKEN,
                false,
                'Inactive'
            );

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        Prospect_Device_Token__c resultValue = [
            SELECT Active__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertEquals(
            false,
            resultValue.Active__c
        );
    }

    /**
     * Tests a blank FCM token.
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Opportunity opportunity =
            createConvertedOpportunity(
                'BlankToken',
                STATUS_MANAGER_APPROVED
            );

        Lead prospect =
            getConvertedLead(opportunity.Id);

        createDevice(
            prospect.Id,
            '',
            true,
            'BlankToken'
        );

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :prospect.Id
            ]
        );
    }

    /**
     * Tests successful manager-approved notification.
     */
    @IsTest
    static void managerApprovedBudgetSendsPush() {

        Opportunity opportunity =
            createConvertedOpportunity(
                'Approved',
                STATUS_MANAGER_APPROVED
            );

        Lead prospect =
            getConvertedLead(opportunity.Id);

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            'Approved'
        );

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        Opportunity resultValue = [
            SELECT Budget_Review_Status__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_MANAGER_APPROVED,
            resultValue.Budget_Review_Status__c
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :prospect.Id
                AND Active__c = true
            ]
        );
    }

    /**
     * Tests multiple active device tokens.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Opportunity opportunity =
            createConvertedOpportunity(
                'MultipleDevices',
                STATUS_MANAGER_APPROVED
            );

        Lead prospect =
            getConvertedLead(opportunity.Id);

        Prospect_Device_Token__c firstDevice =
            createDevice(
                prospect.Id,
                TEST_TOKEN,
                true,
                'First'
            );

        Prospect_Device_Token__c secondDevice =
            createDevice(
                prospect.Id,
                SECOND_TOKEN,
                true,
                'Second'
            );

        firstDevice.Last_Seen__c =
            System.now().addDays(-2);

        secondDevice.Last_Seen__c =
            System.now();

        update new List<Prospect_Device_Token__c>{
            firstDevice,
            secondDevice
        };

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        List<Prospect_Device_Token__c> devices = [
            SELECT Id, FCM_Token__c, Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            ORDER BY Last_Seen__c DESC
        ];

        System.assertEquals(
            2,
            devices.size()
        );

        System.assertEquals(
            SECOND_TOKEN,
            devices[0].FCM_Token__c
        );
    }

    /**
     * Tests mixed valid and invalid budget statuses.
     */
    @IsTest
    static void multipleOpportunitiesProcessedSuccessfully() {

        Opportunity approvedOpportunity =
            createConvertedOpportunity(
                'MultiApproved',
                STATUS_MANAGER_APPROVED
            );

        Opportunity pendingOpportunity =
            createConvertedOpportunity(
                'MultiPending',
                STATUS_SENT
            );

        Lead approvedLead =
            getConvertedLead(
                approvedOpportunity.Id
            );

        Lead pendingLead =
            getConvertedLead(
                pendingOpportunity.Id
            );

        createDevice(
            approvedLead.Id,
            TEST_TOKEN,
            true,
            'MultiApproved'
        );

        createDevice(
            pendingLead.Id,
            SECOND_TOKEN,
            true,
            'MultiPending'
        );

        executeJob(
            new Set<Id>{
                approvedOpportunity.Id,
                pendingOpportunity.Id
            }
        );

        Map<Id, Opportunity> results =
            new Map<Id, Opportunity>([
                SELECT
                    Id,
                    Budget_Review_Status__c
                FROM Opportunity
                WHERE Id IN :new Set<Id>{
                    approvedOpportunity.Id,
                    pendingOpportunity.Id
                }
            ]);

        System.assertEquals(
            STATUS_MANAGER_APPROVED,
            results.get(approvedOpportunity.Id)
                .Budget_Review_Status__c
        );

        System.assertEquals(
            STATUS_SENT,
            results.get(pendingOpportunity.Id)
                .Budget_Review_Status__c
        );
    }

    /**
     * Tests valid and inactive devices together.
     */
    @IsTest
    static void mixedDeviceStatusesHandledCorrectly() {

        Opportunity opportunity =
            createConvertedOpportunity(
                'MixedDevices',
                STATUS_MANAGER_APPROVED
            );

        Lead prospect =
            getConvertedLead(opportunity.Id);

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            false,
            'MixedInactive'
        );

        createDevice(
            prospect.Id,
            SECOND_TOKEN,
            true,
            'MixedActive'
        );

        executeJob(
            new Set<Id>{ opportunity.Id }
        );

        Integer activeDeviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
        ];

        System.assertEquals(
            1,
            activeDeviceCount
        );
    }
}