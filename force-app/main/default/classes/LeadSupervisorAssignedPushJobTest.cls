/**
 * -----------------------------------------------------------------------------
 * Class Name      : LeadSupervisorAssignedPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for LeadSupervisorAssignedPushJob.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class LeadSupervisorAssignedPushJobTest {

    private static final String TEST_TOKEN =
        'test_fcm_token_123';

    private static final String STATUS_OPEN =
        'Open - Not Contacted';

    private static final String APPROVAL_STATUS =
        'Approved';

    private static final String PLATFORM_ANDROID =
        'Android';

    /**
     * Simulates a successful Firebase HTTP response.
     */
    private class FirebaseCalloutMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest requestValue) {

            HttpResponse responseValue = new HttpResponse();

            responseValue.setStatusCode(200);
            responseValue.setStatus('OK');

            responseValue.setHeader(
                'Content-Type',
                'application/json'
            );

            responseValue.setBody(
                '{"name":"projects/test/messages/123"}'
            );

            return responseValue;
        }
    }

    /**
     * Creates a Lead without an assigned supervisor.
     */
    private static Lead createLead(String suffixValue) {

        Lead prospect = new Lead(
            FirstName = 'Test',
            LastName = 'Prospect ' + suffixValue,
            Company = 'Arelia Test Company',
            Status = STATUS_OPEN
        );

        insert prospect;

        return prospect;
    }

    /**
     * Completes Lead approval requirements
     * before assigning a supervisor.
     */
    private static void approveAndAssignSupervisor(Id leadId) {

        update new Lead(
            Id = leadId,
            Project_Request_Submitted__c = true,
            Site_Visit_Manager_Approval__c = true
        );

        update new Lead(
            Id = leadId,
            Approval_Status__c = APPROVAL_STATUS
        );

        update new Lead(
            Id = leadId,
            Supervisor_User__c = UserInfo.getUserId()
        );
    }

    /**
     * Creates a device token associated with a Lead.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String tokenValue,
        Boolean isActive
    ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c();

        device.Prospect_Lead__c = leadId;
        device.FCM_Token__c = tokenValue;
        device.Active__c = isActive;
        device.Platform__c = PLATFORM_ANDROID;
        device.Last_Seen__c = System.now();

        insert device;

        return device;
    }

    /**
     * Registers the Firebase callout mock.
     */
    private static void registerFirebaseMock() {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );
    }

    /**
     * Enqueues the Queueable and returns its job ID.
     */
    private static Id enqueuePushJob(Set<Id> leadIds) {

        Test.startTest();

        Id jobId = System.enqueueJob(
            new LeadSupervisorAssignedPushJob(leadIds)
        );

        Test.stopTest();

        return jobId;
    }

    /**
     * Checks that the Queueable completed without errors.
     */
    private static void assertJobCompleted(Id jobId) {

        AsyncApexJob jobRecord = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(
            'Completed',
            jobRecord.Status,
            'Queueable should complete successfully.'
        );

        System.assertEquals(
            0,
            jobRecord.NumberOfErrors,
            'Queueable should complete without errors.'
        );
    }

    /**
     * Tests null Lead IDs.
     */
    @IsTest
    static void nullLeadIdsReturnsSafely() {

        Id jobId = enqueuePushJob(null);

        assertJobCompleted(jobId);
    }

    /**
     * Tests empty Lead IDs.
     */
    @IsTest
    static void emptyLeadIdsReturnsSafely() {

        Id jobId = enqueuePushJob(
            new Set<Id>()
        );

        assertJobCompleted(jobId);
    }

    /**
     * Tests a Lead without an assigned supervisor.
     */
    @IsTest
    static void leadWithoutSupervisorSkipsPush() {

        Lead prospect = createLead('No Supervisor');

        Id jobId = enqueuePushJob(
            new Set<Id>{prospect.Id}
        );

        assertJobCompleted(jobId);

        Lead resultValue = [
            SELECT Supervisor_User__c
            FROM Lead
            WHERE Id = :prospect.Id
            LIMIT 1
        ];

        System.assertEquals(
            null,
            resultValue.Supervisor_User__c,
            'Lead should not have a supervisor.'
        );
    }

    /**
     * Tests a Lead with a supervisor but no device token.
     */
    @IsTest
    static void leadWithoutDeviceTokenSkipsPush() {

        Lead prospect = createLead('No Device');

        approveAndAssignSupervisor(prospect.Id);

        Id jobId = enqueuePushJob(
            new Set<Id>{prospect.Id}
        );

        assertJobCompleted(jobId);

        Integer deviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
        ];

        System.assertEquals(
            0,
            deviceCount,
            'No device token should exist.'
        );
    }

    /**
     * Tests a Lead with an inactive device token.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Lead prospect = createLead('Inactive Device');

        approveAndAssignSupervisor(prospect.Id);

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            false
        );

        Id jobId = enqueuePushJob(
            new Set<Id>{prospect.Id}
        );

        assertJobCompleted(jobId);

        Integer activeDeviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
        ];

        System.assertEquals(
            0,
            activeDeviceCount,
            'Inactive device must not be selected.'
        );
    }

    /**
     * Tests an active device containing a blank FCM token.
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Lead prospect = createLead('Blank Token');

        approveAndAssignSupervisor(prospect.Id);

        createDevice(
            prospect.Id,
            '',
            true
        );

        Id jobId = enqueuePushJob(
            new Set<Id>{prospect.Id}
        );

        assertJobCompleted(jobId);

        Integer deviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
        ];

        System.assertEquals(
            1,
            deviceCount,
            'The blank-token test device should exist.'
        );
    }

    /**
     * Tests a valid supervisor assignment notification.
     */
    @IsTest
    static void validSupervisorAssignmentSendsPush() {

        Lead prospect = createLead('Valid Push');

        approveAndAssignSupervisor(prospect.Id);

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true
        );

        registerFirebaseMock();

        Id jobId = enqueuePushJob(
            new Set<Id>{prospect.Id}
        );

        System.assertNotEquals(
            null,
            jobId,
            'Queueable job should be created.'
        );

        assertJobCompleted(jobId);
    }

    /**
     * Tests selection of the most recently seen device.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Lead prospect = createLead('Multiple Devices');

        approveAndAssignSupervisor(prospect.Id);

        Prospect_Device_Token__c olderDevice =
            createDevice(
                prospect.Id,
                'older_token',
                true
            );

        olderDevice.Last_Seen__c =
            System.now().addDays(-1);

        update olderDevice;

        Prospect_Device_Token__c latestDevice =
            createDevice(
                prospect.Id,
                'latest_token',
                true
            );

        latestDevice.Last_Seen__c =
            System.now();

        update latestDevice;

        registerFirebaseMock();

        Id jobId = enqueuePushJob(
            new Set<Id>{prospect.Id}
        );

        assertJobCompleted(jobId);

        List<Prospect_Device_Token__c> devices = [
            SELECT Id, FCM_Token__c, Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            ORDER BY Last_Seen__c DESC
        ];

        System.assertEquals(
            'latest_token',
            devices[0].FCM_Token__c,
            'The latest device should be first.'
        );
    }

    /**
     * Tests push processing for multiple Leads.
     */
    @IsTest
    static void multipleLeadsProcessedSuccessfully() {

        Lead firstLead = createLead('First');
        Lead secondLead = createLead('Second');

        approveAndAssignSupervisor(firstLead.Id);
        approveAndAssignSupervisor(secondLead.Id);

        createDevice(
            firstLead.Id,
            'token_first',
            true
        );

        createDevice(
            secondLead.Id,
            'token_second',
            true
        );

        registerFirebaseMock();

        Id jobId = enqueuePushJob(
            new Set<Id>{
                firstLead.Id,
                secondLead.Id
            }
        );

        assertJobCompleted(jobId);

        Integer deviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :new Set<Id>{
                firstLead.Id,
                secondLead.Id
            }
            AND Active__c = true
        ];

        System.assertEquals(
            2,
            deviceCount,
            'Both Leads should have active device tokens.'
        );
    }

    /**
     * Tests a Lead ID that does not exist.
     */
    @IsTest
    static void nonexistentLeadReturnsSafely() {

        Id fakeLeadId =
            (Id) '00Q000000000001AAA';

        Id jobId = enqueuePushJob(
            new Set<Id>{fakeLeadId}
        );

        assertJobCompleted(jobId);
    }

    /**
     * Tests mixed Leads with and without supervisors.
     */
    @IsTest
    static void mixedSupervisorAssignmentsProcessed() {

        Lead assignedLead = createLead('Assigned');
        Lead unassignedLead = createLead('Unassigned');

        approveAndAssignSupervisor(assignedLead.Id);

        createDevice(
            assignedLead.Id,
            'assigned_token',
            true
        );

        createDevice(
            unassignedLead.Id,
            'unassigned_token',
            true
        );

        registerFirebaseMock();

        Id jobId = enqueuePushJob(
            new Set<Id>{
                assignedLead.Id,
                unassignedLead.Id
            }
        );

        assertJobCompleted(jobId);

        Lead resultValue = [
            SELECT Supervisor_User__c
            FROM Lead
            WHERE Id = :unassignedLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            null,
            resultValue.Supervisor_User__c,
            'Unassigned Lead must remain without a supervisor.'
        );
    }
}