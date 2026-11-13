/**
 * -----------------------------------------------------------------------------
 * Class Name      : ArchitectureDesignMobileApiTest
 * Author          : Arelia
 * Created Date    : Oct 14, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 14, 2026
 * Description     : Unit tests for ArchitectureDesignMobileApi.
 *                   Covers GET, POST, file downloads,
 *                   request validation, authorization,
 *                   client decisions, and response handling.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ArchitectureDesignMobileApiTest {

    private static final String BASE_URI =
        '/services/apexrest/registration/lead/architecture-design/';

    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_CHANGES = 'Changes Requested';

    private static final String FILE_TITLE = 'DesignPreview';
    private static final String FILE_CONTENT = 'Test file content';

    private static final Integer HTTP_OK = 200;
    private static final Integer HTTP_BAD_REQUEST = 400;
    private static final Integer HTTP_FORBIDDEN = 403;
    private static final Integer HTTP_NOT_FOUND = 404;
    private static final Integer HTTP_CONFLICT = 409;

    /**
     * Creates reusable records.
     */
    @TestSetup
    static void setupData() {

        Lead leadRecord = new Lead(
            FirstName = 'Architecture',
            LastName = 'PortalTest',
            Company = 'Arelia Test Company',
            Email = 'architecture.test@example.com'
        );

        List<LeadStatus> openStatuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder
            LIMIT 1
        ];

        if (!openStatuses.isEmpty()) {
            leadRecord.Status = openStatuses[0].MasterLabel;
        }

        setAreliaRecordType(leadRecord);

        /*
         * Set prerequisites for existing Arelia
         * Lead approval and conversion validations.
         */
        setFieldIfAvailable(
            leadRecord,
            'Project_Request_Submitted__c',
            true
        );

        setFieldIfAvailable(
            leadRecord,
            'Site_Visit_Manager_Approval__c',
            true
        );

        setFieldIfAvailable(
            leadRecord,
            'Approval_Status__c',
            'Approved'
        );

        insert leadRecord;

        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder
            LIMIT 1
        ];

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(leadRecord.Id);

        conversion.setConvertedStatus(
            convertedStatus.MasterLabel
        );

        conversion.setDoNotCreateOpportunity(false);

        conversion.setOpportunityName(
            'Architecture Test Opportunity'
        );

        Database.LeadConvertResult conversionResult =
            Database.convertLead(conversion);

        System.assert(
            conversionResult.isSuccess(),
            'Test Lead conversion must succeed.'
        );

        Id opportunityId =
            conversionResult.getOpportunityId();

        System.assertNotEquals(
            null,
            opportunityId,
            'Converted Opportunity must exist.'
        );

        /*
         * Architecture Design Name is Auto Number.
         * Salesforce generates it automatically.
         */
        Architecture_Design__c sentDesign =
            new Architecture_Design__c(
                Opportunity__c = opportunityId,
                Status__c = STATUS_SENT,
                External_File_Link__c =
                    'https://drive.google.com/file/d/test'
            );

        Architecture_Design__c approvedDesign =
            new Architecture_Design__c(
                Opportunity__c = opportunityId,
                Status__c = STATUS_APPROVED,
                Comments__c = 'Previously approved'
            );

        insert new List<Architecture_Design__c>{
            sentDesign,
            approvedDesign
        };

        ContentVersion fileVersion = new ContentVersion(
            Title = FILE_TITLE,
            PathOnClient = FILE_TITLE + '.pdf',
            VersionData = Blob.valueOf(FILE_CONTENT),
            FirstPublishLocationId = sentDesign.Id
        );

        insert fileVersion;
    }

    /**
     * Sets the Arelia record type when available.
     */
    private static void setAreliaRecordType(SObject record) {

        Schema.DescribeSObjectResult description =
            record.getSObjectType().getDescribe();

        Map<String, Schema.RecordTypeInfo> recordTypes =
            description.getRecordTypeInfosByName();

        if (recordTypes.containsKey('Arelia')) {

            record.put(
                'RecordTypeId',
                recordTypes.get('Arelia').getRecordTypeId()
            );
        }
    }

    /**
     * Assigns an optional field when it exists
     * and can be created.
     */
    private static void setFieldIfAvailable(
        SObject record,
        String fieldName,
        Object fieldValue
    ) {

        Map<String, Schema.SObjectField> fields =
            record.getSObjectType()
                .getDescribe()
                .fields.getMap();

        if (
            fields.containsKey(fieldName) &&
            fields.get(fieldName).getDescribe().isCreateable()
        ) {
            record.put(fieldName, fieldValue);
        }
    }

    /**
     * Returns the converted test Lead.
     */
    private static Lead getConvertedLead() {

        return [
            SELECT
                Id,
                IsConverted,
                ConvertedAccountId,
                ConvertedOpportunityId
            FROM Lead
            WHERE LastName = 'PortalTest'
            LIMIT 1
        ];
    }

    /**
     * Returns a design for the requested status.
     */
    private static Architecture_Design__c getDesign(
        String designStatus
    ) {

        return [
            SELECT
                Id,
                Name,
                Opportunity__c,
                Status__c,
                Comments__c,
                External_File_Link__c
            FROM Architecture_Design__c
            WHERE Status__c = :designStatus
            LIMIT 1
        ];
    }

    /**
     * Gets the PDF version linked to the test design.
     */
    private static ContentVersion getFileVersion() {

        return [
            SELECT
                Id,
                ContentDocumentId,
                VersionData,
                FileExtension
            FROM ContentVersion
            WHERE Title = :FILE_TITLE
            LIMIT 1
        ];
    }

    /**
     * Configures the REST request and response.
     */
    private static void prepareRequest(
        String httpMethod,
        String resourcePath
    ) {

        RestRequest request = new RestRequest();

        request.requestURI = BASE_URI + resourcePath;
        request.httpMethod = httpMethod;

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    /**
     * Executes an HTTP GET request.
     */
    private static Map<String, Object> executeGet(
        Map<String, String> parameters,
        String resourcePath
    ) {

        prepareRequest('GET', resourcePath);

        if (parameters != null) {
            RestContext.request.params.putAll(parameters);
        }

        ArchitectureDesignMobileApi.doGet();

        return parseJsonResponse();
    }

    /**
     * Executes an HTTP POST request.
     */
    private static Map<String, Object> executePost(
        Object requestBody
    ) {

        prepareRequest('POST', '');

        if (requestBody != null) {

            RestContext.request.requestBody =
                Blob.valueOf(
                    JSON.serialize(requestBody)
                );
        }

        ArchitectureDesignMobileApi.doPost();

        return parseJsonResponse();
    }

    /**
     * Deserializes a JSON response.
     */
    private static Map<String, Object> parseJsonResponse() {

        String responseBody =
            RestContext.response.responseBody.toString();

        return (Map<String, Object>)
            JSON.deserializeUntyped(responseBody);
    }

    /**
     * Creates a client decision request.
     */
    private static Map<String, Object> decisionRequest(
        Id leadId,
        Id opportunityId,
        Id designId,
        String status,
        String comments
    ) {

        return new Map<String, Object>{
            'leadId' => leadId,
            'opportunityId' => opportunityId,
            'designId' => designId,
            'status' => status,
            'comments' => comments
        };
    }

    /**
     * Returns valid GET parameters.
     */
    private static Map<String, String> getParameters() {

        Lead leadRecord = getConvertedLead();

        return new Map<String, String>{
            'leadId' => String.valueOf(leadRecord.Id),
            'opportunityId' =>
                String.valueOf(
                    leadRecord.ConvertedOpportunityId
                )
        };
    }

    /**
     * Returns valid file request parameters.
     */
    private static Map<String, String> fileParameters() {

        Map<String, String> parameters =
            getParameters();

        Architecture_Design__c design =
            getDesign(STATUS_SENT);

        ContentVersion version =
            getFileVersion();

        parameters.put(
            'designId',
            String.valueOf(design.Id)
        );

        parameters.put(
            'versionId',
            String.valueOf(version.Id)
        );

        return parameters;
    }

    /**
     * Asserts HTTP status and success indicator.
     */
    private static void assertResponse(
        Integer expectedStatus,
        Boolean expectedSuccess,
        Map<String, Object> response
    ) {

        System.assertEquals(
            expectedStatus,
            RestContext.response.statusCode,
            'Unexpected HTTP status.'
        );

        System.assertEquals(
            expectedSuccess,
            response.get('success'),
            'Unexpected response success indicator.'
        );
    }

    /**
     * GET: Retrieves all designs for converted Lead.
     */
    @IsTest
    static void getAllDesignsReturnsSuccess() {

        Test.startTest();

        Map<String, Object> response =
            executeGet(getParameters(), '');

        Test.stopTest();

        assertResponse(HTTP_OK, true, response);

        Map<String, Object> data =
            (Map<String, Object>) response.get('data');

        List<Object> designs =
            (List<Object>) data.get('designs');

        System.assertEquals(
            2,
            designs.size(),
            'Both test designs should be returned.'
        );
    }

    /**
     * GET: Validates details and file metadata.
     */
    @IsTest
    static void getSpecificDesignReturnsDetails() {

        Architecture_Design__c design =
            getDesign(STATUS_SENT);

        Map<String, String> parameters =
            getParameters();

        parameters.put(
            'designId',
            String.valueOf(design.Id)
        );

        Test.startTest();

        Map<String, Object> response =
            executeGet(parameters, '');

        Test.stopTest();

        assertResponse(HTTP_OK, true, response);

        Map<String, Object> data =
            (Map<String, Object>) response.get('data');

        List<Object> designs =
            (List<Object>) data.get('designs');

        System.assertEquals(1, designs.size());

        Map<String, Object> designData =
            (Map<String, Object>) designs[0];

        System.assertEquals(
            STATUS_SENT,
            designData.get('status')
        );

        System.assertEquals(
            true,
            designData.get('canApprove')
        );

        System.assertEquals(
            true,
            designData.get('canRequestChanges')
        );

        System.assertEquals(
            'https://drive.google.com/file/d/test',
            designData.get('externalFileLink')
        );

        List<Object> files =
            (List<Object>) designData.get('files');

        System.assertEquals(
            1,
            files.size(),
            'Linked PDF must be returned.'
        );

        Map<String, Object> fileData =
            (Map<String, Object>) files[0];

        System.assertEquals(
            'application/pdf',
            fileData.get('contentType')
        );
    }

    /**
     * GET: Approved designs cannot be approved again.
     */
    @IsTest
    static void getApprovedDesignDisablesActions() {

        Architecture_Design__c design =
            getDesign(STATUS_APPROVED);

        Map<String, String> parameters =
            getParameters();

        parameters.put(
            'designId',
            String.valueOf(design.Id)
        );

        Map<String, Object> response =
            executeGet(parameters, '');

        assertResponse(HTTP_OK, true, response);

        Map<String, Object> data =
            (Map<String, Object>) response.get('data');

        List<Object> designs =
            (List<Object>) data.get('designs');

        Map<String, Object> item =
            (Map<String, Object>) designs[0];

        System.assertEquals(
            false,
            item.get('canApprove')
        );

        System.assertEquals(
            false,
            item.get('canRequestChanges')
        );

        System.assertEquals(
            0,
            ((List<Object>) item.get('files')).size()
        );
    }

    /**
     * GET: Missing Lead ID.
     */
    @IsTest
    static void getMissingLeadReturns400() {

        Map<String, Object> response =
            executeGet(
                new Map<String, String>(),
                ''
            );

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * GET: Invalid Lead ID.
     */
    @IsTest
    static void getInvalidLeadReturns400() {

        Map<String, Object> response =
            executeGet(
                new Map<String, String>{
                    'leadId' => 'invalid-id'
                },
                ''
            );

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * GET: An unconverted Lead cannot access designs.
     */
    @IsTest
    static void getUnconvertedLeadReturns404() {

        Lead leadRecord = new Lead(
            LastName = 'UnconvertedTest',
            Company = 'Arelia Test Company'
        );

        setAreliaRecordType(leadRecord);

        insert leadRecord;

        Map<String, Object> response =
            executeGet(
                new Map<String, String>{
                    'leadId' => String.valueOf(leadRecord.Id)
                },
                ''
            );

        assertResponse(
            HTTP_NOT_FOUND,
            false,
            response
        );
    }

    /**
     * GET: Unauthorized Opportunity.
     */
    @IsTest
    static void getWrongOpportunityReturns403() {

        Map<String, String> parameters =
            getParameters();

        parameters.put(
            'opportunityId',
            String.valueOf(
                getConvertedLead().ConvertedAccountId
            )
        );

        Map<String, Object> response =
            executeGet(parameters, '');

        assertResponse(
            HTTP_FORBIDDEN,
            false,
            response
        );
    }

    /**
     * GET: Nonmatching design produces empty result.
     */
    @IsTest
    static void getUnknownDesignReturnsEmptyList() {

        Map<String, String> parameters =
            getParameters();

        parameters.put(
            'designId',
            String.valueOf(
                getConvertedLead().Id
            )
        );

        Map<String, Object> response =
            executeGet(parameters, '');

        assertResponse(HTTP_OK, true, response);

        Map<String, Object> data =
            (Map<String, Object>) response.get('data');

        System.assertEquals(
            0,
            ((List<Object>) data.get('designs')).size()
        );
    }

    /**
     * POST: Approves design with default comment.
     */
    @IsTest
    static void approveDesignUsesDefaultComment() {

        Lead leadRecord = getConvertedLead();

        Architecture_Design__c design =
            getDesign(STATUS_SENT);

        Map<String, Object> requestBody =
            decisionRequest(
                leadRecord.Id,
                leadRecord.ConvertedOpportunityId,
                design.Id,
                STATUS_APPROVED,
                null
            );

        Test.startTest();

        Map<String, Object> response =
            executePost(requestBody);

        Test.stopTest();

        assertResponse(HTTP_OK, true, response);

        Architecture_Design__c updatedDesign = [
            SELECT Status__c, Comments__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        System.assertEquals(
            STATUS_APPROVED,
            updatedDesign.Status__c
        );

        System.assertEquals(
            'Approved By Client',
            updatedDesign.Comments__c
        );
    }

    /**
     * POST: Approves design using supplied comments.
     */
    @IsTest
    static void approveDesignUsesCustomComment() {

        Lead leadRecord = getConvertedLead();

        Architecture_Design__c design =
            getDesign(STATUS_SENT);

        Map<String, Object> requestBody =
            decisionRequest(
                leadRecord.Id,
                leadRecord.ConvertedOpportunityId,
                design.Id,
                STATUS_APPROVED,
                '  Design looks good  '
            );

        Test.startTest();

        Map<String, Object> response =
            executePost(requestBody);

        Test.stopTest();

        assertResponse(HTTP_OK, true, response);

        Architecture_Design__c updatedDesign = [
            SELECT Status__c, Comments__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        System.assertEquals(
            'Design looks good',
            updatedDesign.Comments__c
        );
    }

    /**
     * POST: Submits requested changes.
     */
    @IsTest
    static void requestChangesUpdatesDesign() {

        Lead leadRecord = getConvertedLead();

        Architecture_Design__c design =
            getDesign(STATUS_SENT);

        Map<String, Object> requestBody =
            decisionRequest(
                leadRecord.Id,
                leadRecord.ConvertedOpportunityId,
                design.Id,
                STATUS_CHANGES,
                '  Update the living room design  '
            );

        Test.startTest();

        Map<String, Object> response =
            executePost(requestBody);

        Test.stopTest();

        assertResponse(HTTP_OK, true, response);

        Architecture_Design__c updatedDesign = [
            SELECT Status__c, Comments__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        System.assertEquals(
            STATUS_CHANGES,
            updatedDesign.Status__c
        );

        System.assertEquals(
            'Update the living room design',
            updatedDesign.Comments__c
        );
    }

    /**
     * POST: Missing request body.
     */
    @IsTest
    static void postMissingBodyReturns400() {

        Map<String, Object> response =
            executePost(null);

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * POST: Missing Lead ID.
     */
    @IsTest
    static void postMissingLeadReturns400() {

        Map<String, Object> response =
            executePost(
                new Map<String, Object>{
                    'status' => STATUS_APPROVED
                }
            );

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * POST: Missing Design ID.
     */
    @IsTest
    static void postMissingDesignReturns400() {

        Map<String, Object> response =
            executePost(
                new Map<String, Object>{
                    'leadId' => getConvertedLead().Id,
                    'status' => STATUS_APPROVED
                }
            );

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * POST: Missing status.
     */
    @IsTest
    static void postMissingStatusReturns400() {

        Map<String, Object> response =
            executePost(
                new Map<String, Object>{
                    'leadId' => getConvertedLead().Id,
                    'designId' => getDesign(STATUS_SENT).Id
                }
            );

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * POST: Unsupported status.
     */
    @IsTest
    static void postInvalidStatusReturns400() {

        Lead leadRecord = getConvertedLead();

        Map<String, Object> response =
            executePost(
                decisionRequest(
                    leadRecord.Id,
                    leadRecord.ConvertedOpportunityId,
                    getDesign(STATUS_SENT).Id,
                    'Rejected',
                    null
                )
            );

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * POST: Comments required for change requests.
     */
    @IsTest
    static void postChangesWithoutCommentsReturns400() {

        Lead leadRecord = getConvertedLead();

        Map<String, Object> response =
            executePost(
                decisionRequest(
                    leadRecord.Id,
                    leadRecord.ConvertedOpportunityId,
                    getDesign(STATUS_SENT).Id,
                    STATUS_CHANGES,
                    null
                )
            );

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * POST: Unconverted Lead returns 404.
     */
    @IsTest
    static void postUnconvertedLeadReturns404() {

        Lead leadRecord = new Lead(
            LastName = 'PostUnconverted',
            Company = 'Arelia Test Company'
        );

        setAreliaRecordType(leadRecord);

        insert leadRecord;

        Map<String, Object> response =
            executePost(
                decisionRequest(
                    leadRecord.Id,
                    null,
                    getDesign(STATUS_SENT).Id,
                    STATUS_APPROVED,
                    null
                )
            );

        assertResponse(
            HTTP_NOT_FOUND,
            false,
            response
        );
    }

    /**
     * POST: Unauthorized Opportunity.
     */
    @IsTest
    static void postWrongOpportunityReturns403() {

        Lead leadRecord = getConvertedLead();

        Map<String, Object> response =
            executePost(
                decisionRequest(
                    leadRecord.Id,
                    leadRecord.ConvertedAccountId,
                    getDesign(STATUS_SENT).Id,
                    STATUS_APPROVED,
                    null
                )
            );

        assertResponse(
            HTTP_FORBIDDEN,
            false,
            response
        );
    }

    /**
     * POST: Design must belong to converted Opportunity.
     */
    @IsTest
    static void postUnknownDesignReturns404() {

        Lead leadRecord = getConvertedLead();

        Map<String, Object> response =
            executePost(
                decisionRequest(
                    leadRecord.Id,
                    leadRecord.ConvertedOpportunityId,
                    leadRecord.Id,
                    STATUS_APPROVED,
                    null
                )
            );

        assertResponse(
            HTTP_NOT_FOUND,
            false,
            response
        );
    }

    /**
     * POST: Already approved design cannot be changed.
     */
    @IsTest
    static void postAlreadyApprovedReturns409() {

        Lead leadRecord = getConvertedLead();

        Map<String, Object> response =
            executePost(
                decisionRequest(
                    leadRecord.Id,
                    leadRecord.ConvertedOpportunityId,
                    getDesign(STATUS_APPROVED).Id,
                    STATUS_CHANGES,
                    'Request another change'
                )
            );

        assertResponse(
            HTTP_CONFLICT,
            false,
            response
        );
    }

    /**
     * GET File: Downloads authorized PDF.
     */
    @IsTest
    static void downloadAuthorizedFileReturns200() {

        prepareRequest('GET', 'file');

        RestContext.request.params.putAll(
            fileParameters()
        );

        Test.startTest();

        ArchitectureDesignMobileApi.doGet();

        Test.stopTest();

        System.assertEquals(
            HTTP_OK,
            RestContext.response.statusCode
        );

        System.assertEquals(
            FILE_CONTENT,
            RestContext.response.responseBody.toString()
        );
    }

    /**
     * GET File: Missing Lead ID.
     */
    @IsTest
    static void downloadMissingLeadReturns400() {

        Map<String, String> parameters =
            fileParameters();

        parameters.remove('leadId');

        Map<String, Object> response =
            executeGet(parameters, 'file');

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * GET File: Missing Design ID.
     */
    @IsTest
    static void downloadMissingDesignReturns400() {

        Map<String, String> parameters =
            fileParameters();

        parameters.remove('designId');

        Map<String, Object> response =
            executeGet(parameters, 'file');

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * GET File: Missing Version ID.
     */
    @IsTest
    static void downloadMissingVersionReturns400() {

        Map<String, String> parameters =
            fileParameters();

        parameters.remove('versionId');

        Map<String, Object> response =
            executeGet(parameters, 'file');

        assertResponse(
            HTTP_BAD_REQUEST,
            false,
            response
        );
    }

    /**
     * GET File: Unauthorized Opportunity.
     */
    @IsTest
    static void downloadWrongOpportunityReturns403() {

        Map<String, String> parameters =
            fileParameters();

        parameters.put(
            'opportunityId',
            String.valueOf(
                getConvertedLead().ConvertedAccountId
            )
        );

        Map<String, Object> response =
            executeGet(parameters, 'file');

        assertResponse(
            HTTP_FORBIDDEN,
            false,
            response
        );
    }

    /**
     * GET File: Rejects file not linked to design.
     */
    @IsTest
    static void downloadUnlinkedFileReturns403() {

        ContentVersion unrelatedFile = new ContentVersion(
            Title = 'UnrelatedFile',
            PathOnClient = 'UnrelatedFile.pdf',
            VersionData = Blob.valueOf('Unrelated content')
        );

        insert unrelatedFile;

        Map<String, String> parameters =
            fileParameters();

        parameters.put(
            'versionId',
            String.valueOf(unrelatedFile.Id)
        );

        Map<String, Object> response =
            executeGet(parameters, 'file');

        assertResponse(
            HTTP_FORBIDDEN,
            false,
            response
        );
    }

    /**
     * GET File: Missing design returns 404.
     */
    @IsTest
    static void downloadUnknownDesignReturns404() {

        Map<String, String> parameters =
            fileParameters();

        parameters.put(
            'designId',
            String.valueOf(getConvertedLead().Id)
        );

        Map<String, Object> response =
            executeGet(parameters, 'file');

        assertResponse(
            HTTP_NOT_FOUND,
            false,
            response
        );
    }

    /**
     * GET File: Unconverted prospect returns 404.
     */
    @IsTest
    static void downloadUnconvertedLeadReturns404() {

        Lead leadRecord = new Lead(
            LastName = 'FileUnconverted',
            Company = 'Arelia Test Company'
        );

        setAreliaRecordType(leadRecord);

        insert leadRecord;

        Map<String, String> parameters =
            fileParameters();

        parameters.put(
            'leadId',
            String.valueOf(leadRecord.Id)
        );

        Map<String, Object> response =
            executeGet(parameters, 'file');

        assertResponse(
            HTTP_NOT_FOUND,
            false,
            response
        );
    }

    /**
     * GET File: Covers supported MIME type mappings.
     */
    @IsTest
    static void downloadDifferentFileTypes() {

        Architecture_Design__c design =
            getDesign(STATUS_SENT);

        List<String> extensions = new List<String>{
            'png',
            'jpg',
            'jpeg',
            'gif',
            'webp',
            'zip',
            'glb',
            'gltf',
            'txt'
        };

        List<ContentVersion> versions =
            new List<ContentVersion>();

        Integer fileCounter = 0;

        for (String extension : extensions) {

            fileCounter++;

            String title =
                'TestFile' + String.valueOf(fileCounter);

            versions.add(
                new ContentVersion(
                    Title = title,
                    PathOnClient = title + '.' + extension,
                    VersionData = Blob.valueOf(
                        'Sample content'
                    ),
                    FirstPublishLocationId = design.Id
                )
            );
        }

        insert versions;

        Set<Id> versionIds = new Set<Id>();

        for (ContentVersion version : versions) {
            versionIds.add(version.Id);
        }

        List<ContentVersion> createdVersions = [
            SELECT Id, FileExtension
            FROM ContentVersion
            WHERE Id IN :versionIds
        ];

        Map<String, String> mimeTypes =
            new Map<String, String>{
                'png' => 'image/png',
                'jpg' => 'image/jpeg',
                'jpeg' => 'image/jpeg',
                'gif' => 'image/gif',
                'webp' => 'image/webp',
                'zip' => 'application/zip',
                'glb' => 'model/gltf-binary',
                'gltf' => 'model/gltf+json',
                'txt' => 'application/octet-stream'
            };

        for (ContentVersion version : createdVersions) {

            Map<String, String> parameters =
                fileParameters();

            parameters.put(
                'versionId',
                String.valueOf(version.Id)
            );

            prepareRequest('GET', 'file');

            RestContext.request.params.putAll(
                parameters
            );

            ArchitectureDesignMobileApi.doGet();

            System.assertEquals(
                HTTP_OK,
                RestContext.response.statusCode,
                'File download failed for ' +
                    version.FileExtension
            );

            System.assertEquals(
                mimeTypes.get(
                    version.FileExtension.toLowerCase()
                ),
                RestContext.response.headers.get(
                    'Content-Type'
                ),
                'Incorrect MIME type.'
            );
        }
    }
}