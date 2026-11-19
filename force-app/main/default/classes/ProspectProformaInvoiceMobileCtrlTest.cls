/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ProspectProformaInvoiceMobileCtrlTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : This test class implements for ProspectProformaInvoiceMobileController
 */

@IsTest
private class ProspectProformaInvoiceMobileCtrlTest {

    private static final String BASE_URI = '/services/apexrest/registration/lead/proforma-invoice/';

    private static final String TEST_PASSWORD =
        'Example123!';

    private static final String TEST_TOKEN =
        'InvoiceTestToken123';

    private static final String STATUS_SENT =
        'Sent';

    private static final String STATUS_APPROVED =
        'Approved';

    private static final String STATUS_CHANGES_REQUESTED =
        'Changes Requested';

    private static final String ACTION_APPROVE =
        'APPROVE';

    private static final String ACTION_REQUEST_CHANGES =
        'REQUEST_CHANGES';

    private static Integer clientSequence = 0;

    /**
     * Creates a unique Lead without converting it.
     *
     * @return Created Lead.
     */
    private static Lead createUnconvertedLead() {

        clientSequence++;

        String suffix =
            String.valueOf(clientSequence);

        Lead lead = new Lead(
            LastName =
                'Invoice Client ' + suffix,
            Company =
                'Arelia Test Company ' + suffix,
            Email =
                'invoice' + suffix + '@example.com',
            Phone =
                '98765432' +
                String.valueOf(10 + clientSequence),
            Enter_Password__c =
                TEST_PASSWORD,
            Confirm_password__c =
                TEST_PASSWORD,
            Site_Visit_Manager_Approval__c =
                true,
            Approval_Status__c =
                'Approved'
        );

        insert lead;

        return lead;
    }

    /**
     * Creates and converts a unique Lead.
     *
     * @return Converted Lead.
     */
    private static Lead createClient() {

        Lead lead =
            createUnconvertedLead();

        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(
            lead.Id
        );

        conversion.setConvertedStatus(
            convertedStatus.MasterLabel
        );

        conversion.setOpportunityName(
            'Invoice Test Project ' +
            String.valueOf(clientSequence)
        );

        Database.LeadConvertResult result =
            Database.convertLead(
                conversion
            );

        System.assertEquals(
            true,
            result.isSuccess(),
            'Lead conversion should succeed.'
        );

        return [
            SELECT
                Id,
                IsConverted,
                ConvertedOpportunityId
            FROM Lead
            WHERE Id = :lead.Id
            LIMIT 1
        ];
    }

    /**
     * Creates a Proforma Invoice.
     *
     * @param lead Converted Lead.
     * @return Created invoice.
     */
    private static Proforma_Invoice__c createInvoice(
        Lead lead
    ) {

        return createInvoice(
            lead,
            TEST_TOKEN
        );
    }

    /**
     * Creates a Proforma Invoice using the supplied token.
     *
     * @param lead Converted Lead.
     * @param secureToken Secure token.
     * @return Created invoice.
     */
    private static Proforma_Invoice__c createInvoice(
        Lead lead,
        String secureToken
    ) {

        Proforma_Invoice__c invoice =
            new Proforma_Invoice__c(
                Opportunity__c =
                    lead.ConvertedOpportunityId,
                Status__c =
                    STATUS_SENT,
                Secure_Token__c =
                    secureToken
            );

        insert invoice;

        return [
            SELECT
                Id,
                Name,
                Opportunity__c,
                Status__c,
                Secure_Token__c,
                Client_Comments__c,
                Related_File_Id__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
            LIMIT 1
        ];
    }

    /**
     * Creates a Salesforce File.
     *
     * @param title File title.
     * @param extension File extension.
     * @return ContentVersion containing ContentDocumentId.
     */
    private static ContentVersion createFile(
        String title,
        String extension
    ) {

        ContentVersion version =
            new ContentVersion(
                Title =
                    title,
                PathOnClient =
                    title + '.' + extension,
                VersionData =
                    Blob.valueOf(
                        'Test Proforma Invoice File'
                    )
            );

        insert version;

        return [
            SELECT
                Id,
                Title,
                FileExtension,
                ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];
    }

    /**
     * Links a ContentDocument to a Proforma Invoice.
     *
     * @param invoiceId Invoice ID.
     * @param contentDocumentId ContentDocument ID.
     */
    private static void linkFile(
        Id invoiceId,
        Id contentDocumentId
    ) {

        ContentDocumentLink link =
            new ContentDocumentLink(
                LinkedEntityId =
                    invoiceId,
                ContentDocumentId =
                    contentDocumentId,
                ShareType =
                    'V'
            );

        insert link;
    }

    /**
     * Initializes GET request context.
     */
    private static void prepareGetRequest() {

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'GET';

        request.requestURI =
            BASE_URI;

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();
    }

    /**
     * Executes exact invoice GET.
     *
     * @param lead Lead.
     * @param invoice Invoice.
     * @param secureToken Token.
     */
    private static void getExactInvoice(
        Lead lead,
        Proforma_Invoice__c invoice,
        String secureToken
    ) {

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'invoiceId',
            String.valueOf(invoice.Id)
        );

        RestContext.request.addParameter(
            'secureToken',
            secureToken
        );

        ProspectProformaInvoiceMobileController.getProformaInvoice();
    }

    /**
     * Executes POST request.
     *
     * @param lead Lead.
     * @param invoice Invoice.
     * @param action Action.
     * @param comments Comments.
     * @param secureToken Token.
     */
    private static void submitResponse(
        Lead lead,
        Proforma_Invoice__c invoice,
        String action,
        String comments,
        String secureToken
    ) {

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'POST';

        request.requestURI =
            BASE_URI;

        request.requestBody =
            Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'leadId' =>
                            lead.Id,
                        'invoiceId' =>
                            invoice.Id,
                        'secureToken' =>
                            secureToken,
                        'action' =>
                            action,
                        'comments' =>
                            comments
                    }
                )
            );

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();

        ProspectProformaInvoiceMobileController.submitProformaResponse();
    }

    /**
     * Reads JSON response.
     *
     * @return Parsed response.
     */
    private static Map<String, Object> readResponse() {

        return (Map<String, Object>)
            JSON.deserializeUntyped(
                RestContext.response
                    .responseBody
                    .toString()
            );
    }

    @IsTest
    static void approvalIsSavedOnlyOnce() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        Test.startTest();

        submitResponse(
            lead,
            invoice,
            ACTION_APPROVE,
            'Accepted',
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Initial approval should succeed.'
        );

        submitResponse(
            lead,
            invoice,
            ACTION_REQUEST_CHANGES,
            'Overwrite',
            invoice.Secure_Token__c
        );

        System.assertEquals(
            409,
            RestContext.response.statusCode,
            'Second response should be rejected.'
        );

        Proforma_Invoice__c savedInvoice = [
            SELECT
                Status__c,
                Client_Comments__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_APPROVED,
            savedInvoice.Status__c,
            'Invoice should remain approved.'
        );

        System.assertEquals(
            'Accepted',
            savedInvoice.Client_Comments__c,
            'Comments should remain unchanged.'
        );
    }

    @IsTest
    static void changesRequireComments() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        submitResponse(
            lead,
            invoice,
            ACTION_REQUEST_CHANGES,
            ' ',
            invoice.Secure_Token__c
        );

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Blank comments should fail.'
        );

        Test.startTest();

        submitResponse(
            lead,
            invoice,
            ACTION_REQUEST_CHANGES,
            ' Revise total ',
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Valid change request should succeed.'
        );

        Proforma_Invoice__c savedInvoice = [
            SELECT
                Status__c,
                Client_Comments__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_CHANGES_REQUESTED,
            savedInvoice.Status__c,
            'Invoice should contain Changes Requested status.'
        );

        System.assertEquals(
            'Revise total',
            savedInvoice.Client_Comments__c,
            'Comments should be trimmed.'
        );
    }

    @IsTest
    static void approvalDefaultsBlankComments() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        Test.startTest();

        submitResponse(
            lead,
            invoice,
            ACTION_APPROVE,
            '   ',
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Approval should succeed.'
        );

        Proforma_Invoice__c savedInvoice = [
            SELECT Client_Comments__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Approved By Client',
            savedInvoice.Client_Comments__c,
            'Default approval comment should be populated.'
        );
    }

    @IsTest
    static void invalidActionIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        Test.startTest();

        submitResponse(
            lead,
            invoice,
            'REJECT',
            'Rejected',
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Unsupported action should fail.'
        );
    }

    @IsTest
    static void wrongTokenAndOpportunityAreRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        submitResponse(
            lead,
            invoice,
            ACTION_APPROVE,
            null,
            'wrong-token'
        );

        System.assertEquals(
            403,
            RestContext.response.statusCode,
            'Wrong token should fail.'
        );

        Lead unrelatedLead =
            createClient();

        submitResponse(
            unrelatedLead,
            invoice,
            ACTION_APPROVE,
            null,
            invoice.Secure_Token__c
        );

        System.assertEquals(
            403,
            RestContext.response.statusCode,
            'Unrelated Opportunity should fail.'
        );
    }

    @IsTest
    static void postWithoutBodyIsRejected() {

        RestContext.request =
            new RestRequest();

        RestContext.request.httpMethod =
            'POST';

        RestContext.request.requestURI =
            BASE_URI;

        RestContext.response =
            new RestResponse();

        Test.startTest();

        ProspectProformaInvoiceMobileController.submitProformaResponse();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing request body should fail.'
        );
    }

    @IsTest
    static void postMissingLeadIsRejected() {

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'POST';

        request.requestURI =
            BASE_URI;

        request.requestBody =
            Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'invoiceId' => 'test',
                        'secureToken' => TEST_TOKEN,
                        'action' => ACTION_APPROVE
                    }
                )
            );

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();

        Test.startTest();

        ProspectProformaInvoiceMobileController.submitProformaResponse();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing lead ID should fail.'
        );
    }

    @IsTest
    static void postMissingInvoiceIsRejected() {

        Lead lead =
            createClient();

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'POST';

        request.requestURI =
            BASE_URI;

        request.requestBody =
            Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'leadId' => lead.Id,
                        'secureToken' => TEST_TOKEN,
                        'action' => ACTION_APPROVE
                    }
                )
            );

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();

        Test.startTest();

        ProspectProformaInvoiceMobileController.submitProformaResponse();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing invoice ID should fail.'
        );
    }

    @IsTest
    static void postMissingTokenIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'POST';

        request.requestURI =
            BASE_URI;

        request.requestBody =
            Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'leadId' => lead.Id,
                        'invoiceId' => invoice.Id,
                        'action' => ACTION_APPROVE
                    }
                )
            );

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();

        Test.startTest();

        ProspectProformaInvoiceMobileController.submitProformaResponse();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing token should fail.'
        );
    }

    @IsTest
    static void postMissingActionIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'POST';

        request.requestURI =
            BASE_URI;

        request.requestBody =
            Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'leadId' => lead.Id,
                        'invoiceId' => invoice.Id,
                        'secureToken' =>
                            invoice.Secure_Token__c
                    }
                )
            );

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();

        Test.startTest();

        ProspectProformaInvoiceMobileController.submitProformaResponse();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing action should fail.'
        );
    }

    @IsTest
    static void profileGetReturnsLatestInvoice() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Profile GET should succeed.'
        );

        Map<String, Object> response =
            readResponse();

        System.assertEquals(
            true,
            response.get('success'),
            'Response should be successful.'
        );

        Map<String, Object> invoiceData =
            (Map<String, Object>)
            response.get('invoice');

        System.assertEquals(
            String.valueOf(invoice.Id),
            String.valueOf(
                invoiceData.get('invoiceId')
            ),
            'Correct invoice should be returned.'
        );
    }

    @IsTest
    static void exactGetReturnsInvoice() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        Test.startTest();

        getExactInvoice(
            lead,
            invoice,
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Exact invoice GET should succeed.'
        );

        Map<String, Object> response =
            readResponse();

        Map<String, Object> invoiceData =
            (Map<String, Object>)
            response.get('invoice');

        System.assertEquals(
            STATUS_SENT,
            invoiceData.get('status'),
            'Invoice status should be returned.'
        );
    }

    @IsTest
    static void exactGetReturnsLinkedFile() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        ContentVersion version =
            createFile(
                'ProformaInvoice',
                'pdf'
            );

        linkFile(
            invoice.Id,
            version.ContentDocumentId
        );

        Test.startTest();

        getExactInvoice(
            lead,
            invoice,
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Invoice with linked file should load.'
        );

        Map<String, Object> response =
            readResponse();

        List<Object> files =
            (List<Object>)
            response.get('files');

        System.assertEquals(
            1,
            files.size(),
            'One linked file should be returned.'
        );

        Map<String, Object> fileData =
            (Map<String, Object>)
            files[0];

        System.assertEquals(
            'ProformaInvoice',
            fileData.get('title'),
            'File title should match.'
        );

        System.assertNotEquals(
            null,
            fileData.get('downloadPath'),
            'Download path should be generated.'
        );
    }

    @IsTest
    static void relatedContentVersionIsReturned() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        ContentVersion version =
            createFile(
                'RelatedInvoice',
                'pdf'
            );

        invoice.Related_File_Id__c =
            String.valueOf(
                version.Id
            );

        update invoice;

        Test.startTest();

        getExactInvoice(
            lead,
            invoice,
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Related ContentVersion should be returned.'
        );

        Map<String, Object> response =
            readResponse();

        List<Object> files =
            (List<Object>)
            response.get('files');

        System.assertEquals(
            1,
            files.size(),
            'Related file should be returned.'
        );
    }

    @IsTest
    static void relatedContentDocumentIsReturned() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        ContentVersion version =
            createFile(
                'DocumentInvoice',
                'pdf'
            );

        invoice.Related_File_Id__c =
            String.valueOf(
                version.ContentDocumentId
            );

        update invoice;

        Test.startTest();

        getExactInvoice(
            lead,
            invoice,
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Related ContentDocument should load.'
        );

        Map<String, Object> response =
            readResponse();

        List<Object> files =
            (List<Object>)
            response.get('files');

        System.assertEquals(
            1,
            files.size(),
            'ContentDocument should be returned.'
        );
    }

    @IsTest
    static void downloadLinkedPdfSucceeds() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        ContentVersion version =
            createFile(
                'DownloadInvoice',
                'pdf'
            );

        linkFile(
            invoice.Id,
            version.ContentDocumentId
        );

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'invoiceId',
            String.valueOf(invoice.Id)
        );

        RestContext.request.addParameter(
            'secureToken',
            invoice.Secure_Token__c
        );

        RestContext.request.addParameter(
            'download',
            'true'
        );

        RestContext.request.addParameter(
            'fileVersionId',
            String.valueOf(version.Id)
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Linked PDF download should succeed.'
        );

        System.assertNotEquals(
            null,
            RestContext.response.responseBody,
            'Downloaded file should contain body.'
        );
    }

    @IsTest
    static void unrelatedFileDownloadIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        ContentVersion unrelatedFile =
            createFile(
                'UnrelatedInvoice',
                'pdf'
            );

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'invoiceId',
            String.valueOf(invoice.Id)
        );

        RestContext.request.addParameter(
            'secureToken',
            invoice.Secure_Token__c
        );

        RestContext.request.addParameter(
            'download',
            'true'
        );

        RestContext.request.addParameter(
            'fileVersionId',
            String.valueOf(unrelatedFile.Id)
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            403,
            RestContext.response.statusCode,
            'Unrelated file should not be downloadable.'
        );
    }

    @IsTest
    static void invalidFileVersionIdIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'invoiceId',
            String.valueOf(invoice.Id)
        );

        RestContext.request.addParameter(
            'secureToken',
            invoice.Secure_Token__c
        );

        RestContext.request.addParameter(
            'download',
            'true'
        );

        RestContext.request.addParameter(
            'fileVersionId',
            'not-an-id'
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid file ID should fail.'
        );
    }

    @IsTest
    static void getWithoutLeadIsRejected() {

        prepareGetRequest();

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing lead ID should fail.'
        );
    }

    @IsTest
    static void getMissingExactParametersIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'invoiceId',
            String.valueOf(invoice.Id)
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing secure token should fail.'
        );
    }

    @IsTest
    static void unconvertedLeadCannotViewInvoice() {

        Lead lead =
            createUnconvertedLead();

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            403,
            RestContext.response.statusCode,
            'Unconverted Lead should be rejected.'
        );
    }

    @IsTest
    static void convertedLeadWithoutInvoiceReturns404() {

        Lead lead =
            createClient();

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'Lead without invoice should return 404.'
        );
    }

    @IsTest
    static void invalidInvoiceIdIsRejected() {

        Lead lead =
            createClient();

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'invoiceId',
            'invalid-id'
        );

        RestContext.request.addParameter(
            'secureToken',
            TEST_TOKEN
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Malformed invoice ID should fail.'
        );
    }

    @IsTest
    static void exactGetWrongTokenIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        Test.startTest();

        getExactInvoice(
            lead,
            invoice,
            'incorrect-token'
        );

        Test.stopTest();

        System.assertEquals(
            403,
            RestContext.response.statusCode,
            'Incorrect token should fail.'
        );
    }

    @IsTest
    static void exactGetWrongLeadIsRejected() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        Lead otherLead =
            createClient();

        Test.startTest();

        getExactInvoice(
            otherLead,
            invoice,
            invoice.Secure_Token__c
        );

        Test.stopTest();

        System.assertEquals(
            403,
            RestContext.response.statusCode,
            'Wrong Lead should not access invoice.'
        );
    }

    @IsTest
    static void listIncludesSentInvoices() {

        Lead lead =
            createClient();

        Proforma_Invoice__c invoice =
            createInvoice(
                lead
            );

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'list',
            'true'
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'List request should succeed.'
        );

        Map<String, Object> response =
            readResponse();

        List<Object> invoices =
            (List<Object>)
            response.get('invoices');

        System.assertEquals(
            1,
            invoices.size(),
            'One invoice should be returned.'
        );

        Map<String, Object> invoiceData =
            (Map<String, Object>)
            invoices[0];

        System.assertEquals(
            String.valueOf(invoice.Id),
            String.valueOf(
                invoiceData.get('invoiceId')
            ),
            'Invoice IDs should match.'
        );
    }

    @IsTest
    static void listUnconvertedLeadReturnsEmptyList() {

        Lead lead =
            createUnconvertedLead();

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(lead.Id)
        );

        RestContext.request.addParameter(
            'list',
            'true'
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Unconverted Lead list request should succeed.'
        );

        Map<String, Object> response =
            readResponse();

        List<Object> invoices =
            (List<Object>)
            response.get('invoices');

        System.assertEquals(
            0,
            invoices.size(),
            'Unconverted Lead should have no invoices.'
        );
    }

    @IsTest
    static void listInvalidLeadIdIsRejected() {

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            'invalid-lead-id'
        );

        RestContext.request.addParameter(
            'list',
            'true'
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid Lead ID should fail.'
        );
    }

    @IsTest
    static void listNonLeadIdIsRejected() {

        prepareGetRequest();

        RestContext.request.addParameter(
            'leadId',
            String.valueOf(
                UserInfo.getUserId()
            )
        );

        RestContext.request.addParameter(
            'list',
            'true'
        );

        Test.startTest();

        ProspectProformaInvoiceMobileController.getProformaInvoice();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Non-Lead Salesforce ID should fail.'
        );
    }
}