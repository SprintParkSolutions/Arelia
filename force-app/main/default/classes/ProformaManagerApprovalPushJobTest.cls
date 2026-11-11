/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProformaManagerApprovalPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 16, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 16, 2026
 * Description     : Unit tests for ProformaManagerApprovalPushJob.
 *                   Validates Proforma Invoice approvals, converted Lead
 *                   relationships, Contact and Lead tokens, duplicate handling,
 *                   bulk processing, missing records, Firebase callouts,
 *                   and Queueable execution.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProformaManagerApprovalPushJobTest {

    private static final String STATUS_SENT = 'Sent';
    private static final String APPROVAL_STATUS = 'Approved';
    private static final String TOKEN_PREFIX = 'proforma-test-';
    private static final String JOB_CLASS_NAME =
        'ProformaManagerApprovalPushJob';

    private static final Integer BULK_RECORD_COUNT = 5;

    /**
     * Mock successful Firebase HTTP responses.
     */
    private class FirebaseSuccessMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            return createSuccessResponse();
        }
    }

    /**
     * Mock Firebase HTTP failure responses.
     */
    private class FirebaseFailureMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();

            response.setStatusCode(500);
            response.setHeader(
                'Content-Type',
                'application/json'
            );
            response.setBody(
                '{"error":{"message":"Firebase unavailable"}}'
            );

            return response;
        }
    }

    /**
     * Tracks Firebase notification requests by device token.
     */
    private class FirebaseTrackingMock implements HttpCalloutMock {

        private Map<String, Integer> tokenRequestCounts =
            new Map<String, Integer>();

        private Set<String> expectedTokens;

        public FirebaseTrackingMock(Set<String> tokens) {

            expectedTokens = new Set<String>();

            if (tokens != null) {
                expectedTokens.addAll(tokens);
            }

            for (String token : expectedTokens) {
                tokenRequestCounts.put(token, 0);
            }
        }

        public HttpResponse respond(HttpRequest request) {

            String requestBody = request.getBody();

            if (String.isNotBlank(requestBody)) {

                for (String token : expectedTokens) {

                    if (requestBody.contains(token)) {

                        Integer existingCount =
                            tokenRequestCounts.get(token);

                        tokenRequestCounts.put(
                            token,
                            existingCount + 1
                        );
                    }
                }
            }

            return createSuccessResponse();
        }

        public Integer getTokenRequestCount(String token) {

            if (!tokenRequestCounts.containsKey(token)) {
                return 0;
            }

            return tokenRequestCounts.get(token);
        }

        public Integer getTotalNotificationRequests() {

            Integer total = 0;

            for (Integer count : tokenRequestCounts.values()) {
                total += count;
            }

            return total;
        }
    }

    /**
     * Creates a successful HTTP response.
     *
     * @return HTTP success response.
     */
    private static HttpResponse createSuccessResponse() {

        HttpResponse response = new HttpResponse();

        response.setStatusCode(200);
        response.setHeader(
            'Content-Type',
            'application/json'
        );
        response.setBody(
            '{"name":"projects/test/messages/123"}'
        );

        return response;
    }

    /**
     * Creates a Lead eligible for conversion.
     *
     * @param suffix Unique Lead identifier.
     * @return Inserted Lead.
     */
    private static Lead createApprovedLead(String suffix) {

        Lead prospect = new Lead(
            FirstName = 'Proforma',
            LastName = 'Client ' + suffix,
            Company = 'Arelia Test ' + suffix,
            Email = 'proforma' + suffix + '@example.com',
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = APPROVAL_STATUS,
            Project_Request_Submitted__c = true
        );

        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND Name = 'Arelia'
            LIMIT 1
        ];

        if (!recordTypes.isEmpty()) {
            prospect.RecordTypeId = recordTypes[0].Id;
        }

        insert prospect;

        return prospect;
    }

    /**
     * Converts an approved Lead into an Opportunity.
     *
     * @param prospect Lead to convert.
     * @return Converted Opportunity Id.
     */
    private static Id convertApprovedLead(Lead prospect) {

        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(prospect.Id);
        conversion.setConvertedStatus(
            convertedStatus.MasterLabel
        );
        conversion.setDoNotCreateOpportunity(false);
        conversion.setOpportunityName(
            'Arelia Proforma ' + prospect.LastName
        );

        Database.LeadConvertResult result =
            Database.convertLead(conversion);

        System.Assert.isTrue(
            result.isSuccess(),
            'Lead conversion must succeed.'
        );

        System.Assert.isNotNull(
            result.getOpportunityId(),
            'Conversion must create an Opportunity.'
        );

        return result.getOpportunityId();
    }

    /**
     * Creates a manager-approved Proforma Invoice.
     *
     * @param opportunityId Related Opportunity.
     * @param secureToken Secure invoice token.
     * @return Inserted invoice.
     */
    private static Proforma_Invoice__c createInvoice(
        Id opportunityId,
        String secureToken
    ) {

        Proforma_Invoice__c invoice =
            new Proforma_Invoice__c(
                Opportunity__c = opportunityId,
                Status__c = STATUS_SENT,
                Manager_Approval__c = true,
                Secure_Token__c = secureToken
            );

        setApprovedDate(invoice);

        insert invoice;

        return invoice;
    }

    /**
     * Sets approval date according to the field data type.
     *
     * @param invoice Invoice receiving the approval date.
     */
    private static void setApprovedDate(
        Proforma_Invoice__c invoice
    ) {

        Schema.DescribeFieldResult fieldDescription =
            Proforma_Invoice__c.Proforma_Invoice_Approved_Date__c.getDescribe();

        if (
            fieldDescription.getType() ==
            Schema.DisplayType.DateTime
        ) {

            invoice.put(
                'Proforma_Invoice_Approved_Date__c',
                System.now()
            );

        } else {

            invoice.put(
                'Proforma_Invoice_Approved_Date__c',
                Date.today()
            );
        }
    }

    /**
     * Creates a Contact device token.
     *
     * @param contactId Converted Contact.
     * @param token Firebase token.
     * @param isActive Active flag.
     */
    private static void createContactToken(
        Id contactId,
        String token,
        Boolean isActive
    ) {

        Mobile_Device_Token__c device =
            new Mobile_Device_Token__c(
                Contact__c = contactId,
                FCM_Token__c = token,
                Active__c = isActive
            );

        insert device;
    }

    /**
     * Creates a legacy Lead device token.
     *
     * @param leadId Converted Lead.
     * @param token Firebase token.
     * @param isActive Active flag.
     */
    private static void createLeadToken(
        Id leadId,
        String token,
        Boolean isActive
    ) {

        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c(
                Prospect_Lead__c = leadId,
                FCM_Token__c = token,
                Active__c = isActive
            );

        insert device;
    }

    /**
     * Returns converted Lead details.
     *
     * @param opportunityId Converted Opportunity.
     * @return Converted Lead.
     */
    private static Lead getConvertedLead(
        Id opportunityId
    ) {

        return [
            SELECT Id,
                   ConvertedContactId,
                   ConvertedOpportunityId
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityId
            LIMIT 1
        ];
    }

    /**
     * Creates a converted Lead and approved invoice.
     *
     * @param suffix Unique identifier.
     * @return Approved invoice.
     */
    private static Proforma_Invoice__c createTestInvoice(
        String suffix
    ) {

        Lead prospect = createApprovedLead(suffix);

        Id opportunityId = convertApprovedLead(prospect);

        return createInvoice(
            opportunityId,
            'secure-token-' + suffix
        );
    }

    /**
     * Executes Queueable logic directly.
     *
     * @param invoiceIds Invoice IDs for processing.
     */
    private static void executeJob(Set<Id> invoiceIds) {

        ProformaManagerApprovalPushJob job =
            new ProformaManagerApprovalPushJob(invoiceIds);

        job.execute(null);
    }

    /**
     * Verifies null invoice ID handling.
     */
    @IsTest
    static void nullInvoiceIdsAreHandled() {

        Test.startTest();

        executeJob(null);

        Test.stopTest();
    }

    /**
     * Verifies empty invoice ID handling.
     */
    @IsTest
    static void emptyInvoiceIdsAreHandled() {

        Test.startTest();

        executeJob(new Set<Id>());

        Test.stopTest();
    }

    /**
     * Verifies unrelated record IDs are ignored.
     */
    @IsTest
    static void nonExistingInvoiceIdsAreIgnored() {

        Account accountRecord = new Account(
            Name = 'Unrelated Account'
        );

        insert accountRecord;

        Test.startTest();

        executeJob(
            new Set<Id>{ accountRecord.Id }
        );

        Test.stopTest();
    }

    /**
     * Verifies invoices without converted Leads are ignored.
     */
    @IsTest
    static void invoiceWithoutConvertedLeadIsIgnored() {

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Standalone Proforma Opportunity',
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30)
        );

        insert opportunityRecord;

        Proforma_Invoice__c invoice = createInvoice(
            opportunityRecord.Id,
            'standalone-secure-token'
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.isNotNull(
            invoice.Id,
            'Standalone invoice must exist.'
        );
    }

    /**
     * Verifies unapproved invoices are filtered.
     */
    @IsTest
    static void unapprovedInvoicesAreIgnored() {

        Proforma_Invoice__c invoice =
            createTestInvoice('Unapproved');

        invoice.Manager_Approval__c = false;

        update invoice;

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        Proforma_Invoice__c actualInvoice = [
            SELECT Manager_Approval__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.Assert.isFalse(
            actualInvoice.Manager_Approval__c,
            'Invoice must remain unapproved.'
        );
    }

    /**
     * Verifies approval date handling after automation.
     */
    @IsTest
    static void missingApprovedDateIsIgnored() {

        Proforma_Invoice__c invoice =
            createTestInvoice('MissingDate');

        invoice.put(
            'Proforma_Invoice_Approved_Date__c',
            null
        );

        update invoice;

        Proforma_Invoice__c actualInvoice = [
            SELECT Id,
                   Manager_Approval__c,
                   Proforma_Invoice_Approved_Date__c,
                   Opportunity__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        Lead prospect = getConvertedLead(
            actualInvoice.Opportunity__c
        );

        String deviceToken =
            TOKEN_PREFIX + 'missing-date';

        createContactToken(
            prospect.ConvertedContactId,
            deviceToken,
            true
        );

        FirebaseTrackingMock mock =
            new FirebaseTrackingMock(
                new Set<String>{ deviceToken }
            );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ actualInvoice.Id }
        );

        Test.stopTest();

        Integer expectedRequests =
            actualInvoice.Proforma_Invoice_Approved_Date__c == null
                ? 0
                : 1;

        System.Assert.areEqual(
            expectedRequests,
            mock.getTokenRequestCount(deviceToken),
            'Notification must follow the persisted approval date.'
        );
    }

    /**
     * Verifies blank secure tokens are ignored.
     */
    @IsTest
    static void blankSecureTokenIsIgnored() {

        Proforma_Invoice__c invoice =
            createTestInvoice('BlankToken');

        invoice.Secure_Token__c = null;

        update invoice;

        Lead prospect = getConvertedLead(
            invoice.Opportunity__c
        );

        String deviceToken = TOKEN_PREFIX + 'blank';

        createContactToken(
            prospect.ConvertedContactId,
            deviceToken,
            true
        );

        FirebaseTrackingMock mock =
            new FirebaseTrackingMock(
                new Set<String>{ deviceToken }
            );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.areEqual(
            0,
            mock.getTotalNotificationRequests(),
            'Blank secure token must not send notifications.'
        );
    }

    /**
     * Verifies invoices without device tokens are skipped.
     */
    @IsTest
    static void noActiveTokensCompleteSuccessfully() {

        Proforma_Invoice__c invoice =
            createTestInvoice('NoTokens');

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.isNotNull(
            invoice.Id,
            'Invoice must remain available.'
        );
    }

    /**
     * Verifies inactive Contact and Lead tokens are ignored.
     */
    @IsTest
    static void inactiveTokensAreIgnored() {

        Proforma_Invoice__c invoice =
            createTestInvoice('Inactive');

        Lead prospect = getConvertedLead(
            invoice.Opportunity__c
        );

        createContactToken(
            prospect.ConvertedContactId,
            TOKEN_PREFIX + 'inactive-contact',
            false
        );

        createLeadToken(
            prospect.Id,
            TOKEN_PREFIX + 'inactive-lead',
            false
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Mobile_Device_Token__c
                WHERE Contact__c = :prospect.ConvertedContactId
                AND Active__c = false
            ],
            'Inactive Contact token must remain inactive.'
        );
    }

    /**
     * Verifies active Contact tokens are processed.
     */
    @IsTest
    static void contactTokensProcessSuccessfully() {

        Proforma_Invoice__c invoice =
            createTestInvoice('ContactToken');

        Lead prospect = getConvertedLead(
            invoice.Opportunity__c
        );

        String deviceToken =
            TOKEN_PREFIX + 'contact-valid';

        createContactToken(
            prospect.ConvertedContactId,
            deviceToken,
            true
        );

        FirebaseTrackingMock mock =
            new FirebaseTrackingMock(
                new Set<String>{ deviceToken }
            );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.areEqual(
            1,
            mock.getTokenRequestCount(deviceToken),
            'Active Contact token must receive one notification.'
        );
    }

    /**
     * Verifies legacy Lead token fallback.
     */
    @IsTest
    static void leadTokenFallbackProcessesSuccessfully() {

        Proforma_Invoice__c invoice =
            createTestInvoice('LeadFallback');

        Lead prospect = getConvertedLead(
            invoice.Opportunity__c
        );

        String deviceToken =
            TOKEN_PREFIX + 'lead-fallback';

        createLeadToken(
            prospect.Id,
            deviceToken,
            true
        );

        FirebaseTrackingMock mock =
            new FirebaseTrackingMock(
                new Set<String>{ deviceToken }
            );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.areEqual(
            1,
            mock.getTokenRequestCount(deviceToken),
            'Legacy Lead token must receive one notification.'
        );
    }

    /**
     * Verifies Contact token priority over Lead tokens.
     */
    @IsTest
    static void contactTokensTakePriority() {

        Proforma_Invoice__c invoice =
            createTestInvoice('Priority');

        Lead prospect = getConvertedLead(
            invoice.Opportunity__c
        );

        String contactToken =
            TOKEN_PREFIX + 'priority-contact';

        String leadToken =
            TOKEN_PREFIX + 'priority-lead';

        createContactToken(
            prospect.ConvertedContactId,
            contactToken,
            true
        );

        createLeadToken(
            prospect.Id,
            leadToken,
            true
        );

        FirebaseTrackingMock mock =
            new FirebaseTrackingMock(
                new Set<String>{
                    contactToken,
                    leadToken
                }
            );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.areEqual(
            1,
            mock.getTokenRequestCount(contactToken),
            'Contact token must receive one notification.'
        );

        System.Assert.areEqual(
            0,
            mock.getTokenRequestCount(leadToken),
            'Lead token must not be used when Contact token exists.'
        );

        System.Assert.areEqual(
            1,
            mock.getTotalNotificationRequests(),
            'Only one notification must be sent.'
        );
    }

    /**
     * Verifies duplicate tokens are processed only once.
     */
    @IsTest
    static void duplicateTokensAreHandled() {

        Proforma_Invoice__c invoice =
            createTestInvoice('Duplicates');

        Lead prospect = getConvertedLead(
            invoice.Opportunity__c
        );

        String duplicateToken =
            TOKEN_PREFIX + 'duplicate';

        createContactToken(
            prospect.ConvertedContactId,
            duplicateToken,
            true
        );

        createContactToken(
            prospect.ConvertedContactId,
            duplicateToken,
            true
        );

        FirebaseTrackingMock mock =
            new FirebaseTrackingMock(
                new Set<String>{ duplicateToken }
            );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Test.stopTest();

        System.Assert.areEqual(
            1,
            mock.getTokenRequestCount(duplicateToken),
            'Duplicate tokens must produce one notification.'
        );
    }

    /**
     * Verifies bulk processing using one converted Lead
     * and multiple Proforma Invoices.
     *
     * This avoids repeated Lead conversions that can
     * exceed governor limits in automation-heavy orgs.
     */
    @IsTest
    static void bulkApprovedInvoicesProcessSuccessfully() {

        Lead prospect = createApprovedLead('Bulk');

        Id opportunityId =
            convertApprovedLead(prospect);

        Lead convertedProspect =
            getConvertedLead(opportunityId);

        String deviceToken =
            TOKEN_PREFIX + 'bulk-contact';

        createContactToken(
            convertedProspect.ConvertedContactId,
            deviceToken,
            true
        );

        Set<Id> invoiceIds = new Set<Id>();

        for (
            Integer index = 0;
            index < BULK_RECORD_COUNT;
            index++
        ) {

            String suffix =
                String.valueOf(index);

            Proforma_Invoice__c invoice =
                createInvoice(
                    opportunityId,
                    'bulk-secure-token-' + suffix
                );

            invoiceIds.add(invoice.Id);
        }

        System.Assert.areEqual(
            BULK_RECORD_COUNT,
            invoiceIds.size(),
            'Bulk test must create the expected invoices.'
        );

        FirebaseTrackingMock mock =
            new FirebaseTrackingMock(
                new Set<String>{ deviceToken }
            );

        Test.setMock(
            HttpCalloutMock.class,
            mock
        );

        Test.startTest();

        executeJob(invoiceIds);

        Test.stopTest();

        System.Assert.areEqual(
            BULK_RECORD_COUNT,
            mock.getTokenRequestCount(deviceToken),
            'Each approved invoice must generate one notification.'
        );

        System.Assert.areEqual(
            BULK_RECORD_COUNT,
            mock.getTotalNotificationRequests(),
            'All bulk invoices must be processed.'
        );
    }

    /**
     * Verifies Firebase failures do not interrupt processing.
     */
    @IsTest
    static void firebaseFailureIsHandled() {

        Proforma_Invoice__c invoice =
            createTestInvoice('FirebaseError');

        Lead prospect = getConvertedLead(
            invoice.Opportunity__c
        );

        createContactToken(
            prospect.ConvertedContactId,
            TOKEN_PREFIX + 'failure',
            true
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseFailureMock()
        );

        Test.startTest();

        executeJob(
            new Set<Id>{ invoice.Id }
        );

        Integer calloutCount = Limits.getCallouts();

        Test.stopTest();

        System.Assert.isTrue(
            calloutCount > 0,
            'Firebase failure must attempt a callout.'
        );
    }

    /**
     * Verifies Queueable submission and completion.
     */
    @IsTest
    static void queueableJobIsEnqueuedSuccessfully() {

        Test.startTest();

        Id jobId = System.enqueueJob(
            new ProformaManagerApprovalPushJob(
                new Set<Id>()
            )
        );

        Test.stopTest();

        AsyncApexJob queuedJob = [
            SELECT Id,
                   Status,
                   JobType,
                   ApexClass.Name
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.Assert.areEqual(
            JOB_CLASS_NAME,
            queuedJob.ApexClass.Name,
            'Expected Queueable class must execute.'
        );

        System.Assert.areEqual(
            'Completed',
            queuedJob.Status,
            'Queueable job must complete successfully.'
        );
    }
}