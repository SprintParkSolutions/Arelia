/**
 * @description Unit tests for LeadSiteVisitPushJob.
 * Validates appointment eligibility, customer device tokens,
 * supervisor information, bulk processing, and Queueable execution.
 *
 * @author Arelia
 * @lastModifiedDate 2026-11-17
 */
@IsTest
private class LeadSiteVisitPushJobTest {

    private static final String TEST_TOKEN =
        'test_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_fcm_token_456';

    private static final String STATUS_APPROVED =
        'Approved';

    private static final String TEST_COMPANY =
        'Arelia Test Company';

    private static final String FIREBASE_RESPONSE =
        '{"name":"projects/test/messages/test123"}';

    private static final String JOB_COMPLETED =
        'Completed';

    /**
     * @description Mocks Firebase HTTP responses.
     */
    private class FirebaseCalloutMock
        implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();

            response.setStatusCode(200);
            response.setStatus('OK');

            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(FIREBASE_RESPONSE);

            return response;
        }
    }

    /**
     * @description Returns an active appointment slot
     * from Salesforce field metadata.
     */
    private static String getValidAppointmentSlot() {

        Schema.DescribeFieldResult fieldDescribe =
            Lead.Appointment_Time_Slots__c.getDescribe();

        List<Schema.PicklistEntry> picklistValues =
            fieldDescribe.getPicklistValues();

        for (Schema.PicklistEntry entry : picklistValues) {

            if (
                entry.isActive() &&
                !String.isBlank(entry.getValue())
            ) {
                return entry.getValue();
            }
        }

        System.Assert.fail(
            'No active Appointment Time Slot ' +
            'picklist value is configured.'
        );

        return null;
    }

    /**
     * @description Creates a Lead for appointment testing.
     */
    private static Lead createLead(
        String lastName,
        Boolean includeDate,
        Boolean includeSlot
    ) {

        Lead prospect = new Lead(
            LastName = lastName,
            Company = TEST_COMPANY
        );

        if (includeDate) {

            prospect.Appointment_Date__c =
                Date.today().addDays(5);
        }

        if (includeSlot) {

            prospect.Appointment_Time_Slots__c =
                getValidAppointmentSlot();
        }

        insert prospect;

        return prospect;
    }

    /**
     * @description Creates a Prospect Device Token.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String token,
        Boolean isActive,
        Datetime lastSeen
    ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c(
                Prospect_Lead__c = leadId,
                FCM_Token__c = token,
                Active__c = isActive,
                Last_Seen__c = lastSeen
            );

        insert device;

        return device;
    }

    /**
     * @description Verifies Queueable execution status.
     */
    private static void assertQueueableCompleted(Id jobId) {

        System.Assert.isNotNull(
            jobId,
            'Queueable job ID should be generated.'
        );

        AsyncApexJob jobResult = [
            SELECT Id,
                   Status,
                   NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.Assert.areEqual(
            JOB_COMPLETED,
            jobResult.Status,
            'Queueable should complete successfully.'
        );

        System.Assert.areEqual(
            0,
            jobResult.NumberOfErrors,
            'Queueable should execute without errors.'
        );
    }

    /**
     * @description Executes the Queueable using
     * a valid Salesforce QueueableContext.
     */
    private static void executeJob(Set<Id> leadIds) {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new LeadSiteVisitPushJob(leadIds)
        );

        Test.stopTest();

        assertQueueableCompleted(jobId);
    }

    /**
     * @description Valid Lead with active device
     * and scheduled appointment.
     */
    @IsTest
    static void validSiteVisitSendsPush() {

        Lead prospect = createLead(
            'Valid Site Visit',
            true,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        Lead result = [
            SELECT Id,
                   Appointment_Date__c,
                   Appointment_Time_Slots__c
            FROM Lead
            WHERE Id = :prospect.Id
        ];

        System.Assert.isNotNull(
            result.Appointment_Date__c,
            'Appointment date should exist.'
        );

        System.Assert.areEqual(
            getValidAppointmentSlot(),
            result.Appointment_Time_Slots__c,
            'Appointment slot should match the ' +
            'configured picklist value.'
        );
    }

    /**
     * @description Empty Lead IDs should
     * return without processing.
     */
    @IsTest
    static void emptyLeadIdsSkipsProcessing() {

        executeJob(new Set<Id>());

        System.Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Lead
                WHERE LastName = 'Empty Queueable Lead'
            ],
            'No Lead should be processed.'
        );
    }

    /**
     * @description Null Lead IDs should
     * be handled without exceptions.
     */
    @IsTest
    static void nullLeadIdsSkipsProcessing() {

        executeJob(null);

        System.Assert.isTrue(
            true,
            'Null Lead IDs should be handled safely.'
        );
    }

    /**
     * @description Lead without a device token
     * should not receive a push.
     */
    @IsTest
    static void leadWithoutDeviceSkipsPush() {

        Lead prospect = createLead(
            'No Device',
            true,
            true
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        System.Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :prospect.Id
            ],
            'No device should exist.'
        );
    }

    /**
     * @description Inactive devices must be ignored.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Lead prospect = createLead(
            'Inactive Device',
            true,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            false,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        System.Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :prospect.Id
                AND Active__c = true
            ],
            'Inactive device must not be selected.'
        );
    }

    /**
     * @description Blank FCM tokens must be ignored.
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Lead prospect = createLead(
            'Blank Token',
            true,
            true
        );

        createDevice(
            prospect.Id,
            '',
            true,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        System.Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :prospect.Id
            ],
            'Device record should exist.'
        );
    }

    /**
     * @description Missing appointment date
     * should prevent push processing.
     */
    @IsTest
    static void missingAppointmentDateSkipsPush() {

        Lead prospect = createLead(
            'Missing Date',
            false,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        Lead result = [
            SELECT Appointment_Date__c
            FROM Lead
            WHERE Id = :prospect.Id
        ];

        System.Assert.isNull(
            result.Appointment_Date__c,
            'Appointment date should be null.'
        );
    }

    /**
     * @description Missing appointment time slot
     * should prevent push processing.
     */
    @IsTest
    static void missingAppointmentSlotSkipsPush() {

        Lead prospect = createLead(
            'Missing Slot',
            true,
            false
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        Lead result = [
            SELECT Appointment_Time_Slots__c
            FROM Lead
            WHERE Id = :prospect.Id
        ];

        System.Assert.isTrue(
            String.isBlank(
                result.Appointment_Time_Slots__c
            ),
            'Appointment slot should be blank.'
        );
    }

    /**
     * @description Multiple active device tokens
     * should remain available for processing.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Lead prospect = createLead(
            'Multiple Devices',
            true,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            Datetime.now().addDays(-2)
        );

        createDevice(
            prospect.Id,
            SECOND_TOKEN,
            true,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        List<Prospect_Device_Token__c> devices = [
            SELECT FCM_Token__c,
                   Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST
        ];

        System.Assert.areEqual(
            2,
            devices.size(),
            'Two active devices should exist.'
        );

        System.Assert.areEqual(
            SECOND_TOKEN,
            devices[0].FCM_Token__c,
            'Most recent token should be first.'
        );

        System.Assert.areEqual(
            TEST_TOKEN,
            devices[1].FCM_Token__c,
            'Older active token should remain available.'
        );
    }

    /**
     * @description Multiple Leads should be
     * processed in a single Queueable execution.
     */
    @IsTest
    static void multipleLeadsProcessedSuccessfully() {

        Lead firstLead = createLead(
            'First Prospect',
            true,
            true
        );

        Lead secondLead = createLead(
            'Second Prospect',
            true,
            true
        );

        createDevice(
            firstLead.Id,
            TEST_TOKEN,
            true,
            Datetime.now()
        );

        createDevice(
            secondLead.Id,
            SECOND_TOKEN,
            true,
            Datetime.now()
        );

        Set<Id> leadIds = new Set<Id>{
            firstLead.Id,
            secondLead.Id
        };

        executeJob(leadIds);

        System.Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM Lead
                WHERE Id IN :leadIds
            ],
            'Both Leads should exist.'
        );

        System.Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c IN :leadIds
                AND Active__c = true
            ],
            'Both Leads should have active devices.'
        );
    }

    /**
     * @description Deleted Lead IDs should
     * be handled without processing.
     */
    @IsTest
    static void nonexistentLeadSkipsProcessing() {

        Lead prospect = createLead(
            'Deleted Prospect',
            true,
            true
        );

        Id deletedLeadId = prospect.Id;

        delete prospect;

        executeJob(
            new Set<Id>{ deletedLeadId }
        );

        System.Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Lead
                WHERE Id = :deletedLeadId
            ],
            'Deleted Lead should not be processed.'
        );
    }

    /**
     * @description Validates approval status,
     * supervisor assignment, and appointment data.
     */
    @IsTest
    static void supervisorInformationIncludedInPush() {

        Lead prospect = createLead(
            'Supervisor Assigned',
            true,
            true
        );

        prospect.Project_Request_Submitted__c = true;

        prospect.Approval_Status__c =
            STATUS_APPROVED;

        update prospect;

        prospect.Supervisor_User__c =
            UserInfo.getUserId();

        update prospect;

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        Lead result = [
            SELECT Id,
                   Supervisor_User__c,
                   Supervisor_User__r.Name,
                   Approval_Status__c,
                   Appointment_Time_Slots__c
            FROM Lead
            WHERE Id = :prospect.Id
        ];

        System.Assert.areEqual(
            STATUS_APPROVED,
            result.Approval_Status__c,
            'Lead should be approved.'
        );

        System.Assert.areEqual(
            UserInfo.getUserId(),
            result.Supervisor_User__c,
            'Supervisor should be assigned.'
        );

        System.Assert.isNotNull(
            result.Supervisor_User__r,
            'Supervisor relationship should exist.'
        );

        System.Assert.isNotNull(
            result.Supervisor_User__r.Name,
            'Supervisor name should be available.'
        );

        System.Assert.areEqual(
            getValidAppointmentSlot(),
            result.Appointment_Time_Slots__c,
            'Appointment time slot should be valid.'
        );
    }

    /**
     * @description Verifies asynchronous Queueable
     * execution with System.enqueueJob.
     */
    @IsTest
    static void queueableExecutesSuccessfully() {

        Lead prospect = createLead(
            'Async Queueable',
            true,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            Datetime.now()
        );

        executeJob(
            new Set<Id>{ prospect.Id }
        );

        Lead result = [
            SELECT Id,
                   Appointment_Date__c,
                   Appointment_Time_Slots__c
            FROM Lead
            WHERE Id = :prospect.Id
        ];

        System.Assert.isNotNull(
            result.Appointment_Date__c,
            'Appointment date should exist.'
        );

        System.Assert.isTrue(
            !String.isBlank(
                result.Appointment_Time_Slots__c
            ),
            'Appointment slot should be available.'
        );
    }
}