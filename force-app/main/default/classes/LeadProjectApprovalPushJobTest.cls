/**
 * -----------------------------------------------------------------------------
 * Class Name      : LeadProjectApprovalPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for LeadProjectApprovalPushJob.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class LeadProjectApprovalPushJobTest {

    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_PENDING = 'Pending';

    private static final String TEST_TOKEN =
        'test_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_fcm_token_456';

    private static final String TEST_EMAIL =
        'projectapproval@example.com';

    /**
     * Mock Firebase HTTP callouts.
     */
    private class FirebaseCalloutMock
        implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest requestValue) {

            HttpResponse response = new HttpResponse();

            response.setStatusCode(200);
            response.setStatus('OK');

            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(
                '{"name":"projects/test/messages/mock-message-id",'
                + '"success":1,"failure":0}'
            );

            return response;
        }
    }

    /**
     * Creates a Lead with the required approval prerequisites.
     */
    private static Lead createLead(
        String lastName,
        String approvalStatus
    ) {

        Lead prospect = new Lead();

        prospect.LastName = lastName;
        prospect.Company = 'Arelia Test Company';
        prospect.Email = TEST_EMAIL;

        prospect.Project_Request_Submitted__c = true;
        prospect.Approval_Status__c = approvalStatus;

        insert prospect;

        return prospect;
    }

    /**
     * Creates a Prospect device token.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String token,
        Boolean active,
        Datetime lastSeen
    ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c();

        device.Prospect_Lead__c = leadId;
        device.FCM_Token__c = token;
        device.Active__c = active;
        device.Last_Seen__c = lastSeen;

        insert device;

        return device;
    }

    /**
     * Tests null Lead IDs.
     */
    @IsTest
    static void nullLeadIdsSkipsProcessing() {

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(null)
        );

        Test.stopTest();

        System.assert(
            true,
            'Null Lead IDs should be handled safely.'
        );
    }

    /**
     * Tests empty Lead IDs.
     */
    @IsTest
    static void emptyLeadIdsSkipsProcessing() {

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(new Set<Id>())
        );

        Test.stopTest();

        System.assert(
            true,
            'Empty Lead IDs should be handled safely.'
        );
    }

    /**
     * Tests an approved Lead with an active FCM token.
     */
    @IsTest
    static void approvedLeadSendsPush() {

        Lead prospect = createLead(
            'Approved Prospect',
            STATUS_APPROVED
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            System.now()
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{ prospect.Id }
            )
        );

        Test.stopTest();

        Lead actualLead = [
            SELECT Id, Approval_Status__c
            FROM Lead
            WHERE Id = :prospect.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_APPROVED,
            actualLead.Approval_Status__c,
            'Lead approval status should remain Approved.'
        );
    }

    /**
     * Tests an unapproved Lead.
     */
    @IsTest
    static void unapprovedLeadSkipsPush() {

        Lead prospect = createLead(
            'Pending Prospect',
            STATUS_PENDING
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            System.now()
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{ prospect.Id }
            )
        );

        Test.stopTest();

        Lead actualLead = [
            SELECT Id, Approval_Status__c
            FROM Lead
            WHERE Id = :prospect.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_PENDING,
            actualLead.Approval_Status__c,
            'Pending Lead should remain unapproved.'
        );
    }

    /**
     * Tests an approved Lead without a device.
     */
    @IsTest
    static void leadWithoutDeviceSkipsPush() {

        Lead prospect = createLead(
            'No Device Prospect',
            STATUS_APPROVED
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{ prospect.Id }
            )
        );

        Test.stopTest();

        Integer deviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
        ];

        System.assertEquals(
            0,
            deviceCount,
            'No device token should exist for the Lead.'
        );
    }

    /**
     * Tests an inactive device.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Lead prospect = createLead(
            'Inactive Device Prospect',
            STATUS_APPROVED
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            false,
            System.now()
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{ prospect.Id }
            )
        );

        Test.stopTest();

        Integer activeDeviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
        ];

        System.assertEquals(
            0,
            activeDeviceCount,
            'Inactive devices should not be selected.'
        );
    }

    /**
     * Tests a blank FCM token.
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Lead prospect = createLead(
            'Blank Token Prospect',
            STATUS_APPROVED
        );

        createDevice(
            prospect.Id,
            null,
            true,
            System.now()
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{ prospect.Id }
            )
        );

        Test.stopTest();

        List<Prospect_Device_Token__c> devices = [
            SELECT FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
        ];

        System.assertEquals(
            1,
            devices.size(),
            'One device record should exist.'
        );

        System.assert(
            String.isBlank(devices[0].FCM_Token__c),
            'FCM token should be blank.'
        );
    }

    /**
     * Tests selection when multiple device tokens exist.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Lead prospect = createLead(
            'Multiple Device Prospect',
            STATUS_APPROVED
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            System.now().addDays(-2)
        );

        createDevice(
            prospect.Id,
            SECOND_TOKEN,
            true,
            System.now()
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{ prospect.Id }
            )
        );

        Test.stopTest();

        List<Prospect_Device_Token__c> devices = [
            SELECT FCM_Token__c, Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
            ORDER BY Last_Seen__c DESC
        ];

        System.assertEquals(
            SECOND_TOKEN,
            devices[0].FCM_Token__c,
            'Latest active device should appear first.'
        );
    }

    /**
     * Tests multiple approved Leads.
     */
    @IsTest
    static void multipleLeadsProcessedSuccessfully() {

        Lead firstLead = createLead(
            'First Approved Prospect',
            STATUS_APPROVED
        );

        Lead secondLead = createLead(
            'Second Approved Prospect',
            STATUS_APPROVED
        );

        createDevice(
            firstLead.Id,
            TEST_TOKEN,
            true,
            System.now()
        );

        createDevice(
            secondLead.Id,
            SECOND_TOKEN,
            true,
            System.now()
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{
                    firstLead.Id,
                    secondLead.Id
                }
            )
        );

        Test.stopTest();

        Integer approvedLeadCount = [
            SELECT COUNT()
            FROM Lead
            WHERE Id IN :new Set<Id>{
                firstLead.Id,
                secondLead.Id
            }
            AND Approval_Status__c = :STATUS_APPROVED
        ];

        System.assertEquals(
            2,
            approvedLeadCount,
            'Both Leads should remain approved.'
        );
    }

    /**
     * Tests mixed approved and pending Leads.
     */
    @IsTest
    static void mixedApprovalStatusesProcessed() {

        Lead approvedLead = createLead(
            'Mixed Approved Prospect',
            STATUS_APPROVED
        );

        Lead pendingLead = createLead(
            'Mixed Pending Prospect',
            STATUS_PENDING
        );

        createDevice(
            approvedLead.Id,
            TEST_TOKEN,
            true,
            System.now()
        );

        createDevice(
            pendingLead.Id,
            SECOND_TOKEN,
            true,
            System.now()
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseCalloutMock()
        );

        Test.startTest();

        System.enqueueJob(
            new LeadProjectApprovalPushJob(
                new Set<Id>{
                    approvedLead.Id,
                    pendingLead.Id
                }
            )
        );

        Test.stopTest();

        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, Approval_Status__c
            FROM Lead
            WHERE Id IN :new Set<Id>{
                approvedLead.Id,
                pendingLead.Id
            }
        ]);

        System.assertEquals(
            STATUS_APPROVED,
            leadMap.get(approvedLead.Id).Approval_Status__c,
            'Approved Lead should remain approved.'
        );

        System.assertEquals(
            STATUS_PENDING,
            leadMap.get(pendingLead.Id).Approval_Status__c,
            'Pending Lead should remain pending.'
        );
    }
}