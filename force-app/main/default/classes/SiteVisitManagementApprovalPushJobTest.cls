/**
 * -----------------------------------------------------------------------------
 * Class Name      : SiteVisitManagementApprovalPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for SiteVisitManagementApprovalPushJob.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class SiteVisitManagementApprovalPushJobTest {

    private static final String TEST_TOKEN =
        'test_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_fcm_token_456';

    /**
     * Mock Firebase HTTP responses.
     */
    private class FirebasePushMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            System.assertNotEquals(
                null,
                request,
                'HTTP request must not be null.'
            );

            HttpResponse response = new HttpResponse();

            response.setStatusCode(200);
            response.setStatus('OK');

            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(
                '{"name":"projects/test/messages/test123"}'
            );

            return response;
        }
    }

    /**
     * Create a unique Lead for each test scenario.
     * Duplicate handling is included for Lead duplicate rules.
     */
    private static Lead createLead(String suffix) {

        String uniqueValue =
            String.valueOf(Crypto.getRandomInteger())
                .replace('-', '') +
            String.valueOf(System.now().getTime());

        Lead prospect = new Lead(
            FirstName = 'Arelia' + suffix,
            LastName = 'Prospect' + uniqueValue,
            Company = 'Arelia Company ' + uniqueValue,
            Email =
                'sitevisit.' + uniqueValue +
                '@example.com',
            Appointment_Completed__c = true
        );

        Database.DMLOptions dmlOptions =
            new Database.DMLOptions();

        dmlOptions.DuplicateRuleHeader.allowSave = true;

        prospect.setOptions(dmlOptions);

        insert prospect;

        System.assertNotEquals(
            null,
            prospect.Id,
            'Test Lead must be created successfully.'
        );

        return prospect;
    }

    /**
     * Create Site Visit Report.
     */
    private static Site_Visit_Report__c createReport(
        Id leadId,
        Boolean managementApproved,
        Boolean finalSubmitted
    ) {

        Site_Visit_Report__c report =
            new Site_Visit_Report__c(
                Lead__c = leadId,
                Management_Approval__c = managementApproved,
                Is_Final_Submitted__c = finalSubmitted
            );

        insert report;

        System.assertNotEquals(
            null,
            report.Id,
            'Site Visit Report must be created.'
        );

        return report;
    }

    /**
     * Create Prospect device token.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String token,
        Boolean active,
        Datetime lastSeen
    ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c(
                Prospect_Lead__c = leadId,
                FCM_Token__c = token,
                Active__c = active,
                Last_Seen__c = lastSeen
            );

        insert device;

        return device;
    }

    /**
     * Execute Queueable with mocked HTTP callout.
     */
    private static void executeJob(Set<Id> reportIds) {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebasePushMock()
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new SiteVisitManagementApprovalPushJob(
                reportIds
            )
        );

        System.assertNotEquals(
            null,
            jobId,
            'Queueable job must be enqueued.'
        );

        Test.stopTest();
    }

    /**
     * Verify successful push for approved report.
     */
    @IsTest
    static void approvedReportSendsPush() {

        Lead prospect = createLead('Approved');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            true,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            System.now()
        );

        executeJob(
            new Set<Id>{ report.Id }
        );

        Site_Visit_Report__c result = [
            SELECT Management_Approval__c,
                   Is_Final_Submitted__c
            FROM Site_Visit_Report__c
            WHERE Id = :report.Id
        ];

        System.assertEquals(
            true,
            result.Management_Approval__c,
            'Management approval must remain true.'
        );

        System.assertEquals(
            true,
            result.Is_Final_Submitted__c,
            'Report must remain finally submitted.'
        );
    }

    /**
     * Verify unapproved reports are skipped.
     */
    @IsTest
    static void unapprovedReportSkipsPush() {

        Lead prospect = createLead('Unapproved');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            false,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            System.now()
        );

        executeJob(
            new Set<Id>{ report.Id }
        );

        Site_Visit_Report__c result = [
            SELECT Management_Approval__c
            FROM Site_Visit_Report__c
            WHERE Id = :report.Id
        ];

        System.assertEquals(
            false,
            result.Management_Approval__c,
            'Unapproved report must remain unapproved.'
        );
    }

    /**
     * Verify reports without final submission are skipped.
     */
    @IsTest
    static void nonFinalReportSkipsPush() {

        Lead prospect = createLead('NonFinal');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            false,
            false
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            true,
            System.now()
        );

        executeJob(
            new Set<Id>{ report.Id }
        );

        Site_Visit_Report__c result = [
            SELECT Is_Final_Submitted__c
            FROM Site_Visit_Report__c
            WHERE Id = :report.Id
        ];

        System.assertEquals(
            false,
            result.Is_Final_Submitted__c,
            'Non-final report must remain incomplete.'
        );
    }

    /**
     * Verify no notification when device does not exist.
     */
    @IsTest
    static void leadWithoutDeviceSkipsPush() {

        Lead prospect = createLead('NoDevice');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            true,
            true
        );

        executeJob(
            new Set<Id>{ report.Id }
        );

        Integer deviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
        ];

        System.assertEquals(
            0,
            deviceCount,
            'No device should exist for this Lead.'
        );
    }

    /**
     * Verify inactive devices do not receive push.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Lead prospect = createLead('Inactive');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            true,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            false,
            System.now()
        );

        executeJob(
            new Set<Id>{ report.Id }
        );

        Integer activeDevices = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
        ];

        System.assertEquals(
            0,
            activeDevices,
            'Inactive devices must be ignored.'
        );
    }

    /**
     * Verify blank tokens do not trigger a push.
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Lead prospect = createLead('BlankToken');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            true,
            true
        );

        createDevice(
            prospect.Id,
            '',
            true,
            System.now()
        );

        executeJob(
            new Set<Id>{ report.Id }
        );

        Integer deviceCount = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
        ];

        System.assertEquals(
            1,
            deviceCount,
            'Device record should exist.'
        );
    }

    /**
     * Verify latest active device is selected.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Lead prospect = createLead('MultiDevice');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            true,
            true
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

        executeJob(
            new Set<Id>{ report.Id }
        );

        List<Prospect_Device_Token__c> devices = [
            SELECT FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST
        ];

        System.assertEquals(
            2,
            devices.size(),
            'Two active devices must exist.'
        );

        System.assertEquals(
            SECOND_TOKEN,
            devices[0].FCM_Token__c,
            'Latest active token must be selected.'
        );
    }

    /**
     * Verify multiple approved reports are processed.
     */
    @IsTest
    static void multipleReportsProcessedSuccessfully() {

        Lead firstLead = createLead('First');

        Lead secondLead = createLead('Second');

        System.assertNotEquals(
            firstLead.Id,
            secondLead.Id,
            'Two different Leads must be created.'
        );

        Site_Visit_Report__c firstReport = createReport(
            firstLead.Id,
            true,
            true
        );

        Site_Visit_Report__c secondReport = createReport(
            secondLead.Id,
            true,
            true
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

        Set<Id> reportIds = new Set<Id>{
            firstReport.Id,
            secondReport.Id
        };

        executeJob(reportIds);

        Integer approvedReports = [
            SELECT COUNT()
            FROM Site_Visit_Report__c
            WHERE Id IN :reportIds
            AND Management_Approval__c = true
            AND Is_Final_Submitted__c = true
        ];

        System.assertEquals(
            2,
            approvedReports,
            'Both reports must remain approved.'
        );
    }

    /**
     * Verify mixed approval states are processed safely.
     */
    @IsTest
    static void mixedReportStatusesHandledCorrectly() {

        Lead firstLead = createLead('MixedFirst');

        Lead secondLead = createLead('MixedSecond');

        System.assertNotEquals(
            firstLead.Id,
            secondLead.Id,
            'Mixed test must use separate Lead records.'
        );

        Site_Visit_Report__c approvedReport = createReport(
            firstLead.Id,
            true,
            true
        );

        Site_Visit_Report__c pendingReport = createReport(
            secondLead.Id,
            false,
            false
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

        Set<Id> reportIds = new Set<Id>{
            approvedReport.Id,
            pendingReport.Id
        };

        executeJob(reportIds);

        List<Site_Visit_Report__c> results = [
            SELECT Id,
                   Management_Approval__c,
                   Is_Final_Submitted__c
            FROM Site_Visit_Report__c
            WHERE Id IN :reportIds
        ];

        System.assertEquals(
            2,
            results.size(),
            'Both report records must exist.'
        );

        Integer qualifyingReports = 0;

        for (Site_Visit_Report__c report : results) {

            if (
                report.Management_Approval__c == true &&
                report.Is_Final_Submitted__c == true
            ) {
                qualifyingReports++;
            }
        }

        System.assertEquals(
            1,
            qualifyingReports,
            'Only approved and submitted report must qualify.'
        );
    }

    /**
     * Verify empty report ID set is handled.
     */
    @IsTest
    static void emptyReportIdsHandledSafely() {

        executeJob(new Set<Id>());

        Integer reportCount = [
            SELECT COUNT()
            FROM Site_Visit_Report__c
        ];

        System.assertEquals(
            0,
            reportCount,
            'No reports should be processed.'
        );
    }

    /**
     * Verify nonexistent report IDs are ignored.
     */
    @IsTest
    static void nonexistentReportSkipsProcessing() {

        Lead prospect = createLead('Nonexistent');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            true,
            true
        );

        Id deletedReportId = report.Id;

        delete report;

        executeJob(
            new Set<Id>{ deletedReportId }
        );

        Integer reportCount = [
            SELECT COUNT()
            FROM Site_Visit_Report__c
            WHERE Id = :deletedReportId
        ];

        System.assertEquals(
            0,
            reportCount,
            'Deleted report should not be processed.'
        );
    }

    /**
     * Verify execution with multiple device states.
     */
    @IsTest
    static void activeDeviceSelectedOverInactive() {

        Lead prospect = createLead('DeviceStates');

        Site_Visit_Report__c report = createReport(
            prospect.Id,
            true,
            true
        );

        createDevice(
            prospect.Id,
            TEST_TOKEN,
            false,
            System.now()
        );

        createDevice(
            prospect.Id,
            SECOND_TOKEN,
            true,
            System.now().addDays(-1)
        );

        executeJob(
            new Set<Id>{ report.Id }
        );

        List<Prospect_Device_Token__c> activeDevices = [
            SELECT FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :prospect.Id
            AND Active__c = true
        ];

        System.assertEquals(
            1,
            activeDevices.size(),
            'Only one active device should be available.'
        );

        System.assertEquals(
            SECOND_TOKEN,
            activeDevices[0].FCM_Token__c,
            'Active device token must be available.'
        );
    }
}