/**
 * -----------------------------------------------------------------------------
 * Class Name      : ArchitectureClientApprovalPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for ArchitectureClientApprovalPushJob.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ArchitectureClientApprovalPushJobTest {

    private static final String STATUS_OPEN = 'Open';

    private static final String STATUS_APPROVED = 'Approved';

    private static final String TEST_TOKEN =
        'test_architecture_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_architecture_fcm_token_456';

    /**
     * Mock Firebase HTTP callouts.
     */
    private class FirebaseMock implements HttpCalloutMock {

        private Integer responseCode;

        FirebaseMock(Integer responseCode) {
            this.responseCode = responseCode;
        }

        public HttpResponse respond(HttpRequest requestValue) {

            System.assertNotEquals(
                null,
                requestValue,
                'HTTP request should not be null.'
            );

            System.assert(
                String.isNotBlank(requestValue.getEndpoint()),
                'Firebase endpoint should be populated.'
            );

            HttpResponse response = new HttpResponse();

            response.setStatusCode(responseCode);

            response.setHeader(
                'Content-Type',
                'application/json'
            );

            if (responseCode == 200) {
                response.setBody(
                    '{"name":"projects/test/messages/123"}'
                );
            } else {
                response.setBody(
                    '{"error":{"message":"Mock Firebase error"}}'
                );
            }

            return response;
        }
    }

    /**
     * Create converted Leads and Opportunities.
     */
    @TestSetup
    static void setupTestData() {

        List<Lead> leads = new List<Lead>();

        for (
            Integer indexValue = 1;
            indexValue <= 2;
            indexValue++
        ) {

            leads.add(
                new Lead(
                    FirstName = 'Architecture',
                    LastName = 'Client' + indexValue,
                    Company = 'Arelia Architecture ' + indexValue,
                    Email = 'architecture.client' +
                        indexValue + '@example.com',
                    Status = STATUS_OPEN,
                    Project_Request_Submitted__c = true,
                    Site_Visit_Manager_Approval__c = true,
                    Approval_Status__c = STATUS_APPROVED
                )
            );
        }

        insert leads;

        String convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ].MasterLabel;

        for (Lead leadRecord : leads) {

            Database.LeadConvert conversion =
                new Database.LeadConvert();

            conversion.setLeadId(leadRecord.Id);

            conversion.setConvertedStatus(
                convertedStatus
            );

            conversion.setDoNotCreateOpportunity(false);

            conversion.setOpportunityName(
                'Architecture Project ' +
                leadRecord.LastName
            );

            conversion.setOwnerId(
                UserInfo.getUserId()
            );

            Database.LeadConvertResult result =
                Database.convertLead(conversion);

            System.assertEquals(
                true,
                result.isSuccess(),
                'Lead conversion should succeed.'
            );

            System.assertNotEquals(
                null,
                result.getOpportunityId(),
                'Converted Opportunity should be created.'
            );
        }
    }

    /**
     * Get converted Leads.
     */
    private static List<Lead> getConvertedLeads() {

        return [
            SELECT
                Id,
                ConvertedOpportunityId,
                IsConverted
            FROM Lead
            WHERE IsConverted = true
            AND Email LIKE 'architecture.client%@example.com'
            ORDER BY LastName ASC
        ];
    }

    /**
     * Get first converted Lead.
     */
    private static Lead getFirstConvertedLead() {

        List<Lead> leads = getConvertedLeads();

        System.assert(
            !leads.isEmpty(),
            'Converted test Lead should exist.'
        );

        return leads[0];
    }

    /**
     * Enable architecture client approval notification.
     */
    private static void enableApproval(Id opportunityId) {

        Opportunity opportunityRecord =
            new Opportunity(
                Id = opportunityId,
                Architecture_Client_Approval_Sent__c = true
            );

        update opportunityRecord;
    }

    /**
     * Create Architecture Design.
     *
     * Name is not assigned because it is read-only.
     */
    private static Architecture_Design__c createDesign(
        Id opportunityId
    ) {

        Architecture_Design__c design =
            new Architecture_Design__c();

        design.Opportunity__c = opportunityId;

        design.Comments__c =
            'Architecture design ready for client review.';

        design.External_File_Link__c =
            'https://drive.google.com/file/d/test/view';

        insert design;

        System.assertNotEquals(
            null,
            design.Id,
            'Architecture Design should be created.'
        );

        return design;
    }

    /**
     * Create Prospect device token.
     *
     * Name is assigned dynamically only when writable.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String fcmToken,
        Boolean isActive
    ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c();

        device.Prospect_Lead__c = leadId;
        device.FCM_Token__c = fcmToken;
        device.Active__c = isActive;
        device.Platform__c = 'Android';
        device.Last_Seen__c = System.now();

        Schema.DescribeFieldResult nameFieldDescribe =
            Schema.SObjectType.Prospect_Device_Token__c
                .fields.Name;

        if (nameFieldDescribe.isCreateable()) {
            device.put(
                'Name',
                'Architecture Test Device'
            );
        }

        insert device;

        System.assertNotEquals(
            null,
            device.Id,
            'Prospect device should be created.'
        );

        return device;
    }

    /**
     * Execute Queueable directly with mocked callouts.
     */
    private static void executeJob(Set<Id> opportunityIds) {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(200)
        );

        Test.startTest();

        ArchitectureClientApprovalPushJob job =
            new ArchitectureClientApprovalPushJob(
                opportunityIds
            );

        job.execute(null);

        Test.stopTest();
    }

    /**
     * Test successful Architecture Design notification.
     */
    @IsTest
    static void validArchitectureDesignSendsPush() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        Architecture_Design__c design = createDesign(
            leadRecord.ConvertedOpportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        System.assertNotEquals(
            null,
            design.Id,
            'Valid Architecture Design should exist.'
        );

        Opportunity updatedOpportunity = [
            SELECT Architecture_Client_Approval_Sent__c
            FROM Opportunity
            WHERE Id = :leadRecord.ConvertedOpportunityId
        ];

        System.assertEquals(
            true,
            updatedOpportunity
                .Architecture_Client_Approval_Sent__c,
            'Architecture approval should remain sent.'
        );
    }

    /**
     * Test constructor with null Opportunity IDs.
     */
    @IsTest
    static void nullOpportunityIdsHandled() {

        Test.startTest();

        ArchitectureClientApprovalPushJob job =
            new ArchitectureClientApprovalPushJob(null);

        job.execute(null);

        Test.stopTest();

        System.assertNotEquals(
            null,
            job,
            'Queueable should handle null input.'
        );
    }

    /**
     * Test constructor with empty Opportunity IDs.
     */
    @IsTest
    static void emptyOpportunityIdsHandled() {

        Test.startTest();

        ArchitectureClientApprovalPushJob job =
            new ArchitectureClientApprovalPushJob(
                new Set<Id>()
            );

        job.execute(null);

        Test.stopTest();

        System.assertNotEquals(
            null,
            job,
            'Queueable should handle empty input.'
        );
    }

    /**
     * Test nonexistent Opportunity.
     */
    @IsTest
    static void nonexistentOpportunitySkipsProcessing() {

        Id nonexistentId =
            '006000000000001AAA';

        executeJob(
            new Set<Id>{
                nonexistentId
            }
        );

        Integer opportunityCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Id = :nonexistentId
        ];

        System.assertEquals(
            0,
            opportunityCount,
            'Nonexistent Opportunity should not be found.'
        );
    }

    /**
     * Test Opportunity without converted Lead.
     */
    @IsTest
    static void opportunityWithoutConvertedLeadSkipsPush() {

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Standalone Architecture Project',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Architecture_Client_Approval_Sent__c = true
        );

        insert opportunityRecord;

        createDesign(
            opportunityRecord.Id
        );

        executeJob(
            new Set<Id>{
                opportunityRecord.Id
            }
        );

        Integer convertedLeadCount = [
            SELECT COUNT()
            FROM Lead
            WHERE ConvertedOpportunityId =
                :opportunityRecord.Id
        ];

        System.assertEquals(
            0,
            convertedLeadCount,
            'Standalone Opportunity should not have converted Lead.'
        );
    }

    /**
     * Test approval flag is false.
     */
    @IsTest
    static void approvalNotSentSkipsPush() {

        Lead leadRecord = getFirstConvertedLead();

        createDesign(
            leadRecord.ConvertedOpportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        Opportunity opportunityRecord = [
            SELECT Architecture_Client_Approval_Sent__c
            FROM Opportunity
            WHERE Id = :leadRecord.ConvertedOpportunityId
        ];

        System.assertNotEquals(
            true,
            opportunityRecord
                .Architecture_Client_Approval_Sent__c,
            'Approval should not be marked as sent.'
        );
    }

    /**
     * Test missing Architecture Design.
     */
    @IsTest
    static void missingArchitectureDesignSkipsPush() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        Integer designCount = [
            SELECT COUNT()
            FROM Architecture_Design__c
            WHERE Opportunity__c =
                :leadRecord.ConvertedOpportunityId
        ];

        System.assertEquals(
            0,
            designCount,
            'No Architecture Design should exist.'
        );
    }

    /**
     * Test missing Prospect device token.
     */
    @IsTest
    static void missingDeviceTokenSkipsPush() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        createDesign(
            leadRecord.ConvertedOpportunityId
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        Integer tokenCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :leadRecord.Id
        ];

        System.assertEquals(
            0,
            tokenCount,
            'No device token should exist.'
        );
    }

    /**
     * Test inactive Prospect device.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        createDesign(
            leadRecord.ConvertedOpportunityId
        );

        Prospect_Device_Token__c device = createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            false
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        Prospect_Device_Token__c storedDevice = [
            SELECT Active__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertEquals(
            false,
            storedDevice.Active__c,
            'Inactive device should remain inactive.'
        );
    }

    /**
     * Test blank FCM token.
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        createDesign(
            leadRecord.ConvertedOpportunityId
        );

        Prospect_Device_Token__c device = createDevice(
            leadRecord.Id,
            '',
            true
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        Prospect_Device_Token__c storedDevice = [
            SELECT FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assert(
            String.isBlank(
                storedDevice.FCM_Token__c
            ),
            'Blank FCM token should be ignored.'
        );
    }

    /**
     * Test multiple devices for same Lead.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        createDesign(
            leadRecord.ConvertedOpportunityId
        );

        Prospect_Device_Token__c oldDevice = createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true
        );

        oldDevice.Last_Seen__c =
            System.now().addDays(-5);

        update oldDevice;

        Prospect_Device_Token__c newDevice = createDevice(
            leadRecord.Id,
            SECOND_TOKEN,
            true
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        List<Prospect_Device_Token__c> devices = [
            SELECT FCM_Token__c, Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :leadRecord.Id
            AND Active__c = true
            ORDER BY Last_Seen__c DESC
            NULLS LAST
        ];

        System.assertEquals(
            newDevice.FCM_Token__c,
            devices[0].FCM_Token__c,
            'Latest device token should be selected.'
        );
    }

    /**
     * Test multiple Architecture Designs.
     */
    @IsTest
    static void multipleDesignsUsesLatestRecord() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        Architecture_Design__c oldDesign = createDesign(
            leadRecord.ConvertedOpportunityId
        );

        Architecture_Design__c latestDesign = createDesign(
            leadRecord.ConvertedOpportunityId
        );

        Test.setCreatedDate(
            oldDesign.Id,
            System.now().addDays(-3)
        );

        Test.setCreatedDate(
            latestDesign.Id,
            System.now().addDays(-1)
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true
        );

        executeJob(
            new Set<Id>{
                leadRecord.ConvertedOpportunityId
            }
        );

        List<Architecture_Design__c> designs = [
            SELECT Id, CreatedDate
            FROM Architecture_Design__c
            WHERE Opportunity__c =
                :leadRecord.ConvertedOpportunityId
            ORDER BY CreatedDate DESC
        ];

        System.assertEquals(
            latestDesign.Id,
            designs[0].Id,
            'Latest Architecture Design should be selected.'
        );
    }

    /**
     * Test multiple Opportunities.
     */
    @IsTest
    static void multipleOpportunitiesProcessedSuccessfully() {

        List<Lead> convertedLeads = getConvertedLeads();

        Set<Id> opportunityIds = new Set<Id>();

        for (Lead leadRecord : convertedLeads) {

            enableApproval(
                leadRecord.ConvertedOpportunityId
            );

            createDesign(
                leadRecord.ConvertedOpportunityId
            );

            createDevice(
                leadRecord.Id,
                TEST_TOKEN + String.valueOf(leadRecord.Id),
                true
            );

            opportunityIds.add(
                leadRecord.ConvertedOpportunityId
            );
        }

        executeJob(opportunityIds);

        Integer approvalCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Id IN :opportunityIds
            AND Architecture_Client_Approval_Sent__c = true
        ];

        System.assertEquals(
            convertedLeads.size(),
            approvalCount,
            'All Opportunities should remain approved for notification.'
        );
    }

    /**
     * Test mixed approval statuses.
     */
    @IsTest
    static void mixedApprovalStatusesHandledCorrectly() {

        List<Lead> convertedLeads = getConvertedLeads();

        Lead approvedLead = convertedLeads[0];
        Lead pendingLead = convertedLeads[1];

        enableApproval(
            approvedLead.ConvertedOpportunityId
        );

        createDesign(
            approvedLead.ConvertedOpportunityId
        );

        createDesign(
            pendingLead.ConvertedOpportunityId
        );

        createDevice(
            approvedLead.Id,
            TEST_TOKEN,
            true
        );

        createDevice(
            pendingLead.Id,
            SECOND_TOKEN,
            true
        );

        Set<Id> opportunityIds = new Set<Id>{
            approvedLead.ConvertedOpportunityId,
            pendingLead.ConvertedOpportunityId
        };

        executeJob(opportunityIds);

        Map<Id, Opportunity> opportunities =
            new Map<Id, Opportunity>([
                SELECT
                    Id,
                    Architecture_Client_Approval_Sent__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);

        System.assertEquals(
            true,
            opportunities.get(
                approvedLead.ConvertedOpportunityId
            ).Architecture_Client_Approval_Sent__c,
            'Approved Opportunity should remain eligible.'
        );

        System.assertNotEquals(
            true,
            opportunities.get(
                pendingLead.ConvertedOpportunityId
            ).Architecture_Client_Approval_Sent__c,
            'Pending Opportunity should not be eligible.'
        );
    }

    /**
     * Test actual Queueable execution.
     */
    @IsTest
    static void queueableExecutesSuccessfully() {

        Lead leadRecord = getFirstConvertedLead();

        enableApproval(
            leadRecord.ConvertedOpportunityId
        );

        createDesign(
            leadRecord.ConvertedOpportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(200)
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new ArchitectureClientApprovalPushJob(
                new Set<Id>{
                    leadRecord.ConvertedOpportunityId
                }
            )
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Queueable job should be enqueued.'
        );

        AsyncApexJob jobRecord = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(
            'Completed',
            jobRecord.Status,
            'Queueable should complete successfully.'
        );
    }
}