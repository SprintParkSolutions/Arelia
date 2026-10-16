/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProspectSiteVisitReportApiTest
 * Author          : Arelia
 * Created Date    : Oct 7, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 7, 2026
 * Description     : Test class for ProspectSiteVisitReportRestController.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProspectSiteVisitReportApiTest {

    private static final String ENDPOINT =
        '/services/apexrest/registration/lead/site-visit-report/';

    private static final String LEAD_EMAIL =
        'sitevisit.report.client@example.com';

    private static final String SECOND_LEAD_EMAIL =
        'sitevisit.report.other@example.com';

    private static final String FILE_TITLE =
        'Site Visit Blueprint';

    private static final String FILE_PATH =
        'SiteVisitBlueprint.png';

    private static final String FILE_BODY =
        'Sample Site Visit Report file content';

    /**
     * Creates reusable Lead records.
     */
    @TestSetup
    static void setupData() {
        List<Lead> leads = new List<Lead>{
            createLead(
                'Site Visit Client',
                LEAD_EMAIL
            ),
            createLead(
                'Other Client',
                SECOND_LEAD_EMAIL
            )
        };

        insert leads;
    }

    /**
     * Verifies latest approved report retrieval using only leadId.
     */
    @IsTest
    static void latestApprovedReportReturns200() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                clientLead.Id,
                true,
                true
            );

        insert reportRecord;

        ContentVersion fileVersion =
            createFile(
                reportRecord.Id,
                FILE_TITLE,
                FILE_PATH
            );

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                null,
                null
            );

        System.assertEquals(
            200,
            responseValue.statusCode,
            'Approved report should be returned.'
        );

        Map<String, Object> responseBody =
            deserializeResponse(responseValue);

        System.assertEquals(
            true,
            responseBody.get('success'),
            'Response should indicate success.'
        );

        System.assertEquals(
            true,
            responseBody.get('reportAvailable'),
            'Approved report should be available.'
        );

        Map<String, Object> reportData =
            (Map<String, Object>) responseBody.get('report');

        System.assertEquals(
            String.valueOf(reportRecord.Id),
            String.valueOf(reportData.get('reportId')),
            'Correct report should be returned.'
        );

        List<Object> documents =
            (List<Object>) responseBody.get('documents');

        System.assertEquals(
            1,
            documents.size(),
            'One linked document should be returned.'
        );

        Map<String, Object> documentData =
            (Map<String, Object>) documents[0];

        System.assertEquals(
            String.valueOf(fileVersion.Id),
            String.valueOf(documentData.get('versionId')),
            'Latest file version should be returned.'
        );

        System.assertEquals(
            true,
            documentData.get('isImage'),
            'PNG document should be identified as an image.'
        );
    }

    /**
     * Verifies retrieval of a specific approved report.
     */
    @IsTest
    static void specificApprovedReportReturns200() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                clientLead.Id,
                true,
                true
            );

        insert reportRecord;

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                reportRecord.Id,
                null
            );

        System.assertEquals(
            200,
            responseValue.statusCode,
            'Specific approved report should be returned.'
        );

        Map<String, Object> responseBody =
            deserializeResponse(responseValue);

        System.assertEquals(
            true,
            responseBody.get('success'),
            'Response should indicate success.'
        );

        Map<String, Object> reportData =
            (Map<String, Object>) responseBody.get('report');

        System.assertEquals(
            String.valueOf(reportRecord.Id),
            String.valueOf(reportData.get('reportId')),
            'Requested report should be returned.'
        );
    }

    /**
     * Verifies streaming of a document linked to the report.
     */
    @IsTest
    static void linkedDocumentReturns200() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                clientLead.Id,
                true,
                true
            );

        insert reportRecord;

        ContentVersion fileVersion =
            createFile(
                reportRecord.Id,
                'Site Report',
                'SiteReport.pdf'
            );

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                reportRecord.Id,
                fileVersion.Id
            );

        System.assertEquals(
            200,
            responseValue.statusCode,
            'Linked file should be returned.'
        );

        System.assertEquals(
            FILE_BODY,
            responseValue.responseBody.toString(),
            'Returned file data should match uploaded file.'
        );

        System.assertEquals(
            'application/pdf',
            responseValue.headers.get('Content-Type'),
            'PDF MIME type should be returned.'
        );

        String disposition =
            responseValue.headers.get(
                'Content-Disposition'
            );

        System.assert(
            disposition.contains('inline;'),
            'Document should be displayed inline.'
        );
    }

    /**
     * Verifies missing leadId validation.
     */
    @IsTest
    static void missingLeadIdReturns400() {
        RestResponse responseValue =
            executeRawRequest(
                null,
                null,
                null
            );

        assertErrorResponse(
            responseValue,
            400,
            'Valid Lead ID is required.'
        );
    }

    /**
     * Verifies malformed leadId validation.
     */
    @IsTest
    static void invalidLeadIdReturns400() {
        RestRequest requestValue = createRequest();

        requestValue.addParameter(
            'leadId',
            'invalid-lead-id'
        );

        RestResponse responseValue =
            invokeController(requestValue);

        assertErrorResponse(
            responseValue,
            400,
            'Valid Lead ID is required.'
        );
    }

    /**
     * Verifies that an ID belonging to another object
     * cannot be supplied as leadId.
     */
    @IsTest
    static void wrongLeadObjectTypeReturns400() {
        Account accountRecord = new Account(
            Name = 'Site Visit Test Account'
        );
        insert accountRecord;

        RestRequest requestValue = createRequest();

        requestValue.addParameter(
            'leadId',
            accountRecord.Id
        );

        RestResponse responseValue =
            invokeController(requestValue);

        assertErrorResponse(
            responseValue,
            400,
            'Valid Lead ID is required.'
        );
    }

    /**
     * Verifies that versionId cannot be supplied
     * without reportId.
     */
    @IsTest
    static void versionWithoutReportReturns400() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                clientLead.Id,
                true,
                true
            );

        insert reportRecord;

        ContentVersion fileVersion =
            createFile(
                reportRecord.Id,
                FILE_TITLE,
                FILE_PATH
            );

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                null,
                fileVersion.Id
            );

        assertErrorResponse(
            responseValue,
            400,
            'Valid Site Visit Report ID is required'
        );
    }

    /**
     * Verifies malformed reportId validation.
     */
    @IsTest
    static void invalidReportIdReturns400() {
        Lead clientLead = getLead(LEAD_EMAIL);

        RestRequest requestValue = createRequest();

        requestValue.addParameter(
            'leadId',
            clientLead.Id
        );

        requestValue.addParameter(
            'reportId',
            'invalid-report-id'
        );

        RestResponse responseValue =
            invokeController(requestValue);

        assertErrorResponse(
            responseValue,
            400,
            'Valid Site Visit Report ID is required.'
        );
    }

    /**
     * Verifies reportId object-type validation.
     */
    @IsTest
    static void wrongReportObjectTypeReturns400() {
        Lead clientLead = getLead(LEAD_EMAIL);

        RestResponse responseValue =
            executeRawRequest(
                String.valueOf(clientLead.Id),
                String.valueOf(clientLead.Id),
                null
            );

        assertErrorResponse(
            responseValue,
            400,
            'Valid Site Visit Report ID is required.'
        );
    }

    /**
     * Verifies ContentVersion object-type validation.
     */
    @IsTest
    static void wrongVersionObjectTypeReturns400() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                clientLead.Id,
                true,
                true
            );

        insert reportRecord;

        RestResponse responseValue =
            executeRawRequest(
                String.valueOf(clientLead.Id),
                String.valueOf(reportRecord.Id),
                String.valueOf(clientLead.Id)
            );

        assertErrorResponse(
            responseValue,
            400,
            'Valid Content Version ID is required.'
        );
    }

    /**
     * Verifies latest-report request when no
     * approved report exists.
     */
    @IsTest
    static void noApprovedReportReturns404() {
        Lead clientLead = getLead(LEAD_EMAIL);

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                null,
                null
            );

        assertErrorResponse(
            responseValue,
            404,
            'No final-submitted and management-approved'
        );
    }

    /**
     * Verifies that one Lead cannot access
     * another Lead's report.
     */
    @IsTest
    static void reportForDifferentLeadReturns404() {
        Lead clientLead = getLead(LEAD_EMAIL);
        Lead otherLead = getLead(SECOND_LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                otherLead.Id,
                true,
                true
            );

        insert reportRecord;

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                reportRecord.Id,
                null
            );

        assertErrorResponse(
            responseValue,
            404,
            'does not belong to the logged-in Prospect'
        );
    }

    /**
     * Verifies a non-final submitted report
     * cannot be accessed.
     */
    @IsTest
    static void nonFinalReportReturns404() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                clientLead.Id,
                false,
                true
            );

        insert reportRecord;

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                reportRecord.Id,
                null
            );

        assertErrorResponse(
            responseValue,
            404,
            'not final submitted'
        );
    }

    /**
     * Verifies a report without management approval
     * cannot be accessed.
     */
    @IsTest
    static void unapprovedReportReturns404() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c reportRecord =
            createReport(
                clientLead.Id,
                true,
                false
            );

        insert reportRecord;

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                reportRecord.Id,
                null
            );

        assertErrorResponse(
            responseValue,
            404,
            'not approved by management'
        );
    }

    /**
     * Verifies that a document belonging to a different
     * report cannot be downloaded.
     */
    @IsTest
    static void documentNotLinkedToReportReturns404() {
        Lead clientLead = getLead(LEAD_EMAIL);

        Site_Visit_Report__c requestedReport =
            createReport(
                clientLead.Id,
                true,
                true
            );

        Site_Visit_Report__c otherReport =
            createReport(
                clientLead.Id,
                true,
                true
            );

        insert new List<Site_Visit_Report__c>{
            requestedReport,
            otherReport
        };

        ContentVersion otherFile =
            createFile(
                otherReport.Id,
                'Other Report File',
                'OtherReportFile.txt'
            );

        RestResponse responseValue =
            executeRequest(
                clientLead.Id,
                requestedReport.Id,
                otherFile.Id
            );

        assertErrorResponse(
            responseValue,
            404,
            'not linked to this report'
        );
    }

    /**
     * Creates a Lead used by the test methods.
     */
    private static Lead createLead(
        String lastName,
        String emailValue
    ) {
        return new Lead(
            LastName = lastName,
            Company = 'Arelia Test Client',
            Email = emailValue,
            Phone = '9876543210',
            Appointment_Completed__c = true
        );
    }

    /**
     * Creates a Site Visit Report.
     */
    private static Site_Visit_Report__c createReport(
        Id leadId,
        Boolean finalSubmitted,
        Boolean managementApproved
    ) {
        return new Site_Visit_Report__c(
            Lead__c = leadId,
            Is_Final_Submitted__c = finalSubmitted,
            Management_Approval__c = managementApproved
        );
    }

    /**
     * Creates and publishes a Salesforce File directly
     * against the supplied report.
     */
    private static ContentVersion createFile(
        Id reportId,
        String titleValue,
        String pathValue
    ) {
        ContentVersion versionRecord =
            new ContentVersion(
                Title = titleValue,
                PathOnClient = pathValue,
                VersionData = Blob.valueOf(FILE_BODY),
                FirstPublishLocationId = reportId
            );

        insert versionRecord;

        return [
            SELECT
                Id,
                ContentDocumentId,
                Title,
                FileExtension
            FROM ContentVersion
            WHERE Id = :versionRecord.Id
            LIMIT 1
        ];
    }

    /**
     * Returns a setup Lead.
     */
    private static Lead getLead(String emailValue) {
        return [
            SELECT
                Id,
                Email,
                Appointment_Completed__c
            FROM Lead
            WHERE Email = :emailValue
            LIMIT 1
        ];
    }

    /**
     * Executes the REST endpoint using Salesforce IDs.
     */
    private static RestResponse executeRequest(
        Id leadId,
        Id reportId,
        Id versionId
    ) {
        return executeRawRequest(
            leadId == null
                ? null
                : String.valueOf(leadId),
            reportId == null
                ? null
                : String.valueOf(reportId),
            versionId == null
                ? null
                : String.valueOf(versionId)
        );
    }

    /**
     * Executes the REST endpoint using raw values.
     */
    private static RestResponse executeRawRequest(
        String leadId,
        String reportId,
        String versionId
    ) {
        RestRequest requestValue = createRequest();

        if (String.isNotBlank(leadId)) {
            requestValue.addParameter(
                'leadId',
                leadId
            );
        }

        if (String.isNotBlank(reportId)) {
            requestValue.addParameter(
                'reportId',
                reportId
            );
        }

        if (String.isNotBlank(versionId)) {
            requestValue.addParameter(
                'versionId',
                versionId
            );
        }

        return invokeController(requestValue);
    }

    /**
     * Creates a standard REST GET request.
     */
    private static RestRequest createRequest() {
        RestRequest requestValue = new RestRequest();

        requestValue.requestUri = ENDPOINT;
        requestValue.httpMethod = 'GET';

        return requestValue;
    }

    /**
     * Invokes the REST controller.
     */
    private static RestResponse invokeController(
        RestRequest requestValue
    ) {
        RestContext.request = requestValue;
        RestContext.response = new RestResponse();

        Test.startTest();

        ProspectSiteVisitReportRestController.getReportOrDocument();

        Test.stopTest();

        return RestContext.response;
    }

    /**
     * Converts a JSON REST response into a map.
     */
    private static Map<String, Object> deserializeResponse(
        RestResponse responseValue
    ) {
        return (Map<String, Object>)
            JSON.deserializeUntyped(
                responseValue.responseBody.toString()
            );
    }

    /**
     * Validates a standard API error response.
     */
    private static void assertErrorResponse(
        RestResponse responseValue,
        Integer expectedStatusCode,
        String expectedMessage
    ) {
        System.assertEquals(
            expectedStatusCode,
            responseValue.statusCode,
            'Unexpected HTTP status code.'
        );

        Map<String, Object> responseBody =
            deserializeResponse(responseValue);

        System.assertEquals(
            false,
            responseBody.get('success'),
            'Error response should indicate failure.'
        );

        System.assertEquals(
            false,
            responseBody.get('reportAvailable'),
            'Report should not be available.'
        );

        String actualMessage =
            String.valueOf(
                responseBody.get('message')
            );

        System.assert(
            actualMessage.contains(expectedMessage),
            'Unexpected response message. Actual: '
                + actualMessage
        );
    }
}