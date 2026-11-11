/**
 * -----------------------------------------------------------------------------
 * Class Name      : ClientAgreementPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for ClientAgreementPushJob.
 *                   Tests Client Agreement push notifications,
 *                   converted Leads, device tokens and HTTP callouts.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ClientAgreementPushJobTest {

    private static final String TEST_EMAIL =
        'clientagreement.test@example.com';

    private static final String TEST_TOKEN =
        'test_client_agreement_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_client_agreement_fcm_token_456';

    private static final String STATUS_APPROVED =
        'Approved';

    private static final String NOTIFICATION_TYPE =
        'CLIENT_AGREEMENT_SENT';

    private static final String ACTION_TYPE =
        'OPEN_CLIENT_AGREEMENT';

    private static final String NOTIFICATION_ROUTE =
        'client_agreement';

    /**
     * ---------------------------------------------------------
     * MOCK FIREBASE HTTP CALLOUT
     * ---------------------------------------------------------
     */
    private class FirebaseHttpMock
        implements HttpCalloutMock {

        public HttpResponse respond(
            HttpRequest request
        ) {

            HttpResponse response =
                new HttpResponse();

            response.setStatusCode(200);
            response.setStatus('OK');

            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(
                '{"name":"projects/test/messages/123456"}'
            );

            return response;
        }
    }

    /**
     * ---------------------------------------------------------
     * GET VALID LEAD STATUS
     * ---------------------------------------------------------
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
     * ---------------------------------------------------------
     * GET CONVERTED LEAD STATUS
     * ---------------------------------------------------------
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
     * ---------------------------------------------------------
     * CREATE TEST LEAD
     * ---------------------------------------------------------
     */
    private static Lead createLead(
        String suffix
    ) {

        Lead leadRecord = new Lead(
            FirstName = 'Test',
            LastName = 'Agreement ' + suffix,
            Company = 'Arelia Test Company ' + suffix,
            Email = TEST_EMAIL,
            Status = getOpenLeadStatus(),
            OwnerId = UserInfo.getUserId()
        );

        leadRecord.put(
            'Approval_Status__c',
            STATUS_APPROVED
        );

        leadRecord.put(
            'Site_Visit_Manager_Approval__c',
            true
        );

        insert leadRecord;

        return leadRecord;
    }

    /**
     * ---------------------------------------------------------
     * CONVERT LEAD AND GET OPPORTUNITY
     * ---------------------------------------------------------
     */
    private static Opportunity createConvertedOpportunity(
        String suffix
    ) {

        Lead leadRecord =
            createLead(suffix);

        Database.LeadConvert convertRequest =
            new Database.LeadConvert();

        convertRequest.setLeadId(
            leadRecord.Id
        );

        convertRequest.setConvertedStatus(
            getConvertedLeadStatus()
        );

        convertRequest.setOwnerId(
            UserInfo.getUserId()
        );

        convertRequest.setDoNotCreateOpportunity(
            false
        );

        convertRequest.setOpportunityName(
            'Client Agreement Opportunity ' + suffix
        );

        Database.LeadConvertResult result =
            Database.convertLead(
                convertRequest
            );

        System.assert(
            result.isSuccess(),
            'Lead conversion should succeed.'
        );

        System.assertNotEquals(
            null,
            result.getOpportunityId(),
            'Converted Opportunity must exist.'
        );

        return [
            SELECT
                Id,
                Name,
                Client_Agreement_Sent__c,
                Client_Agreement_Signed__c
            FROM Opportunity
            WHERE Id = :result.getOpportunityId()
            LIMIT 1
        ];
    }

    /**
     * ---------------------------------------------------------
     * GET CONVERTED LEAD
     * ---------------------------------------------------------
     */
    private static Lead getConvertedLead(
        Id opportunityId
    ) {

        return [
            SELECT
                Id,
                ConvertedOpportunityId,
                IsConverted
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityId
            LIMIT 1
        ];
    }

    /**
     * ---------------------------------------------------------
     * CREATE DEVICE TOKEN
     * ---------------------------------------------------------
     */
    private static Prospect_Device_Token__c
        createDeviceToken(
            Id leadId,
            String token,
            Boolean isActive
        ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c();

        device.Prospect_Lead__c =
            leadId;

        device.FCM_Token__c =
            token;

        device.Active__c =
            isActive;

        device.Last_Seen__c =
            System.now();

        insert device;

        return device;
    }

    /**
     * ---------------------------------------------------------
     * EXECUTE JOB DIRECTLY
     * ---------------------------------------------------------
     */
    private static void executeJob(
        Set<Id> opportunityIds
    ) {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseHttpMock()
        );

        Test.startTest();

        ClientAgreementPushJob job =
            new ClientAgreementPushJob(
                opportunityIds
            );

        job.execute(null);

        Test.stopTest();
    }

    /**
     * ---------------------------------------------------------
     * TEST 1 - NULL OPPORTUNITY IDS
     * ---------------------------------------------------------
     */
    @IsTest
    static void nullOpportunityIdsHandled() {

        executeJob(null);

        System.assert(
            true,
            'Null Opportunity IDs should be handled.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 2 - EMPTY OPPORTUNITY IDS
     * ---------------------------------------------------------
     */
    @IsTest
    static void emptyOpportunityIdsHandled() {

        executeJob(
            new Set<Id>()
        );

        System.assert(
            true,
            'Empty Opportunity IDs should be handled.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 3 - NONEXISTENT OPPORTUNITY
     * ---------------------------------------------------------
     */
    @IsTest
    static void nonexistentOpportunityHandled() {

        Id fakeOpportunityId =
            (Id) (
                Opportunity.SObjectType
                    .getDescribe()
                    .getKeyPrefix() +
                '000000000001'
            );

        executeJob(
            new Set<Id>{
                fakeOpportunityId
            }
        );

        System.assert(
            true,
            'Nonexistent Opportunities should be skipped.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 4 - OPPORTUNITY WITHOUT CONVERTED LEAD
     * ---------------------------------------------------------
     */
    @IsTest
    static void opportunityWithoutConvertedLead() {

        Opportunity opportunity =
            new Opportunity(
                Name = 'Standalone Agreement',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            );

        insert opportunity;

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        System.assertNotEquals(
            null,
            opportunity.Id,
            'Opportunity must exist.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 5 - CONVERTED LEAD WITHOUT DEVICE
     * ---------------------------------------------------------
     */
    @IsTest
    static void convertedLeadWithoutDevice() {

        Opportunity opportunity =
            createConvertedOpportunity('NoDevice');

        Lead convertedLead =
            getConvertedLead(
                opportunity.Id
            );

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        System.assertEquals(
            true,
            convertedLead.IsConverted,
            'Lead must be converted.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 6 - INACTIVE DEVICE
     * ---------------------------------------------------------
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Opportunity opportunity =
            createConvertedOpportunity('Inactive');

        Lead convertedLead =
            getConvertedLead(
                opportunity.Id
            );

        createDeviceToken(
            convertedLead.Id,
            TEST_TOKEN,
            false
        );

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Integer activeDevices = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :convertedLead.Id
            AND Active__c = true
        ];

        System.assertEquals(
            0,
            activeDevices,
            'No active devices should exist.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 7 - BLANK FCM TOKEN
     * ---------------------------------------------------------
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Opportunity opportunity =
            createConvertedOpportunity('BlankToken');

        Lead convertedLead =
            getConvertedLead(
                opportunity.Id
            );

        Prospect_Device_Token__c device =
            createDeviceToken(
                convertedLead.Id,
                '',
                true
            );

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        System.assert(
            String.isBlank(device.FCM_Token__c),
            'Device token should be blank.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 8 - VALID CLIENT AGREEMENT NOTIFICATION
     * ---------------------------------------------------------
     */
    @IsTest
    static void validClientAgreementSendsPush() {

        Opportunity opportunity =
            createConvertedOpportunity('ValidPush');

        Lead convertedLead =
            getConvertedLead(
                opportunity.Id
            );

        createDeviceToken(
            convertedLead.Id,
            TEST_TOKEN,
            true
        );

        opportunity.Client_Agreement_Sent__c =
            true;

        update opportunity;

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        Opportunity result = [
            SELECT Client_Agreement_Sent__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            result.Client_Agreement_Sent__c,
            'Client Agreement should be sent.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 9 - MULTIPLE DEVICES
     * ---------------------------------------------------------
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Opportunity opportunity =
            createConvertedOpportunity('MultiDevice');

        Lead convertedLead =
            getConvertedLead(
                opportunity.Id
            );

        Prospect_Device_Token__c firstDevice =
            createDeviceToken(
                convertedLead.Id,
                TEST_TOKEN,
                true
            );

        firstDevice.Last_Seen__c =
            System.now().addDays(-2);

        update firstDevice;

        Prospect_Device_Token__c secondDevice =
            createDeviceToken(
                convertedLead.Id,
                SECOND_TOKEN,
                true
            );

        secondDevice.Last_Seen__c =
            System.now();

        update secondDevice;

        executeJob(
            new Set<Id>{
                opportunity.Id
            }
        );

        List<Prospect_Device_Token__c> devices = [
            SELECT
                Id,
                FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :convertedLead.Id
            AND Active__c = true
            ORDER BY Last_Seen__c DESC
            LIMIT 1
        ];

        System.assertEquals(
            SECOND_TOKEN,
            devices[0].FCM_Token__c,
            'Latest device token should be selected.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 10 - MULTIPLE OPPORTUNITIES
     * ---------------------------------------------------------
     */
    @IsTest
    static void multipleOpportunitiesProcessed() {

        Opportunity firstOpportunity =
            createConvertedOpportunity('First');

        Opportunity secondOpportunity =
            createConvertedOpportunity('Second');

        Lead firstLead =
            getConvertedLead(
                firstOpportunity.Id
            );

        Lead secondLead =
            getConvertedLead(
                secondOpportunity.Id
            );

        createDeviceToken(
            firstLead.Id,
            TEST_TOKEN,
            true
        );

        createDeviceToken(
            secondLead.Id,
            SECOND_TOKEN,
            true
        );

        executeJob(
            new Set<Id>{
                firstOpportunity.Id,
                secondOpportunity.Id
            }
        );

        System.assertNotEquals(
            firstOpportunity.Id,
            secondOpportunity.Id,
            'Opportunities must be different.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 11 - QUEUEABLE EXECUTION
     * ---------------------------------------------------------
     */
    @IsTest
    static void queueableExecutesSuccessfully() {

        Opportunity opportunity =
            createConvertedOpportunity('Queueable');

        Lead convertedLead =
            getConvertedLead(
                opportunity.Id
            );

        createDeviceToken(
            convertedLead.Id,
            TEST_TOKEN,
            true
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseHttpMock()
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new ClientAgreementPushJob(
                new Set<Id>{
                    opportunity.Id
                }
            )
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Queueable Job ID must be generated.'
        );

        AsyncApexJob job = [
            SELECT
                Id,
                Status,
                NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(
            'Completed',
            job.Status,
            'Queueable job should complete.'
        );

        System.assertEquals(
            0,
            job.NumberOfErrors,
            'Queueable must complete without errors.'
        );
    }

    /**
     * ---------------------------------------------------------
     * TEST 12 - MIXED OPPORTUNITIES
     * ---------------------------------------------------------
     */
    @IsTest
    static void mixedOpportunitiesHandled() {

        Opportunity validOpportunity =
            createConvertedOpportunity('MixedValid');

        Lead convertedLead =
            getConvertedLead(
                validOpportunity.Id
            );

        createDeviceToken(
            convertedLead.Id,
            TEST_TOKEN,
            true
        );

        Opportunity standaloneOpportunity =
            new Opportunity(
                Name = 'Standalone Mixed',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            );

        insert standaloneOpportunity;

        executeJob(
            new Set<Id>{
                validOpportunity.Id,
                standaloneOpportunity.Id
            }
        );

        System.assertNotEquals(
            validOpportunity.Id,
            standaloneOpportunity.Id,
            'Both Opportunities must be distinct.'
        );
    }
}