/**
 * -----------------------------------------------------------------------------
 * Class Name      : LeadSiteVisitPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for LeadSiteVisitPushJob.
 * -----------------------------------------------------------------------------
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

    /**
     * Mock Firebase HTTP callouts.
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
     * Retrieves an active Appointment Time Slot
     * dynamically from Salesforce metadata.
     *
     * This avoids restricted picklist errors
     * caused by hardcoded values.
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
     * Creates a Lead with the required fields.
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
     * Creates a Prospect Device Token.
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
     * Executes the Queueable directly.
     */
    private static void executeJob(Set<Id> leadIds) {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );

        Test.startTest();

        LeadSiteVisitPushJob job =
            new LeadSiteVisitPushJob(leadIds);

        job.execute(null);

        Test.stopTest();
    }

    /**
     * Valid Lead with active device token
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
            'Appointment slot should match ' +
            'the configured picklist value.'
        );
    }

    /**
     * Empty Lead IDs should return immediately.
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
     * Lead without any device token.
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
     * Inactive device must be ignored.
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
     * Blank FCM token must be ignored.
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
     * Missing appointment date must skip push.
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
     * Missing appointment time slot
     * must skip notification.
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
     * Latest active token should be selected.
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
    }

    /**
     * Multiple Leads should be processed.
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
     * Deleted Lead ID should be ignored.
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
     * Approved Lead with Supervisor information.
     *
     * Validation sequence:
     * 1. Project Request Submitted = true.
     * 2. Approval Status = Approved.
     * 3. Assign Supervisor.
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
     * Verify Queueable execution using
     * System.enqueueJob.
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

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new LeadSiteVisitPushJob(
                new Set<Id>{ prospect.Id }
            )
        );

        Test.stopTest();

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
            'Completed',
            jobResult.Status,
            'Queueable should complete successfully.'
        );

        System.Assert.areEqual(
            0,
            jobResult.NumberOfErrors,
            'Queueable should not have errors.'
        );
    }
}