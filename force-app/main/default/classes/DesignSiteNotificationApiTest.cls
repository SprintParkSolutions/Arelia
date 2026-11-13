/**
 * -----------------------------------------------------------------------------
 * Class Name      : DesignSiteNotificationApiTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : Test class for ArchitectureDesignSiteNotificationApi.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class DesignSiteNotificationApiTest {

    private static final String BASE_ENDPOINT =
        '/services/apexrest/registration/opportunity/'
        + 'design-notification-approvals/';

    private static final String FILE_ENDPOINT = BASE_ENDPOINT + 'file';

    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_CHANGES_REQUESTED = 'Changes Requested';

    private static final String APPROVED_BY_CLIENT = 'Approved By Client';

    private static final String CLIENT_EMAIL =
        'design-client@example.com';

    private static final String EXTERNAL_FILE_LINK =
        'https://drive.google.com/file/d/example/view';

    /**
     * Creates a Contact, Opportunity, and Architecture Design record.
     *
     * @return Architecture Design test record.
     */
    private static Architecture_Design__c createDesignFixture() {
        Contact client = createContact(
            'Design Client',
            CLIENT_EMAIL
        );

        Opportunity project = createOpportunity(
            'Design Review Test',
            client.Id
        );

        return createArchitectureDesign(
            project.Id,
            'Client design'
        );
    }

    /**
     * Creates a Contact.
     *
     * @param lastName Contact last name.
     * @param email Contact email address.
     * @return Inserted Contact.
     */
    private static Contact createContact(
        String lastName,
        String email
    ) {
        Contact client = new Contact(
            LastName = lastName,
            Email = email
        );

        insert client;

        return client;
    }

    /**
     * Creates an Opportunity.
     *
     * @param opportunityName Opportunity name.
     * @param contactId Primary Contact Id.
     * @return Inserted Opportunity.
     */
    private static Opportunity createOpportunity(
        String opportunityName,
        Id contactId
    ) {
        OpportunityStage activeStage = [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
            LIMIT 1
        ];

        Opportunity project = new Opportunity(
            Name = opportunityName,
            StageName = activeStage.MasterLabel,
            CloseDate = Date.today().addDays(30),
            Primary_Contact__c = contactId
        );

        insert project;

        return project;
    }

    /**
     * Creates an Architecture Design record.
     *
     * @param opportunityId Related Opportunity Id.
     * @param designName Design name when Name is not auto-numbered.
     * @return Inserted Architecture Design.
     */
    private static Architecture_Design__c createArchitectureDesign(
        Id opportunityId,
        String designName
    ) {
        Architecture_Design__c design = new Architecture_Design__c(
            Opportunity__c = opportunityId,
            Status__c = STATUS_SENT
        );

        if (!Architecture_Design__c.Name.getDescribe().isAutoNumber()) {
            design.put('Name', designName);
        }

        insert design;

        return design;
    }

    /**
     * Returns the primary Contact associated with the design Opportunity.
     *
     * @param design Architecture Design record.
     * @return Primary Contact Id.
     */
    private static Id getClientId(
        Architecture_Design__c design
    ) {
        Opportunity project = [
            SELECT Primary_Contact__c
            FROM Opportunity
            WHERE Id = :design.Opportunity__c
            LIMIT 1
        ];

        return project.Primary_Contact__c;
    }

    /**
     * Configures RestContext for the supplied endpoint.
     *
     * @param endpoint REST endpoint.
     * @param httpMethod HTTP method.
     */
    private static void configureRestContext(
        String endpoint,
        String httpMethod
    ) {
        RestRequest request = new RestRequest();
        request.requestURI = endpoint;
        request.httpMethod = httpMethod;

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    /**
     * Submits an Architecture Design decision.
     *
     * @param design Design record.
     * @param contactId Contact Id.
     * @param status Decision status.
     * @param comments Decision comments.
     */
    private static void submitDecision(
        Architecture_Design__c design,
        Id contactId,
        String status,
        String comments
    ) {
        configureRestContext(
            BASE_ENDPOINT,
            'POST'
        );

        Map<String, Object> requestBody = new Map<String, Object>{
            'contactId' => contactId,
            'opportunityId' => design.Opportunity__c,
            'designId' => design.Id,
            'status' => status,
            'comments' => comments
        };

        RestContext.request.requestBody = Blob.valueOf(
            JSON.serialize(requestBody)
        );

        ArchitectureDesignSiteNotificationApi.submitDecision();
    }

    /**
     * Calls the design file endpoint.
     *
     * @param design Design record.
     * @param contactId Contact Id.
     * @param versionId Content Version Id.
     */
    private static void requestFile(
        Architecture_Design__c design,
        Id contactId,
        Id versionId
    ) {
        configureRestContext(
            FILE_ENDPOINT,
            'GET'
        );

        RestContext.request.addParameter(
            'contactId',
            String.valueOf(contactId)
        );

        RestContext.request.addParameter(
            'opportunityId',
            String.valueOf(design.Opportunity__c)
        );

        RestContext.request.addParameter(
            'designId',
            String.valueOf(design.Id)
        );

        RestContext.request.addParameter(
            'versionId',
            String.valueOf(versionId)
        );

        ArchitectureDesignSiteNotificationApi.getApprovals();
    }

    /**
     * Calls the design approvals GET endpoint.
     *
     * @param contactId Contact Id.
     */
    private static void requestApprovals(Id contactId) {
        configureRestContext(
            BASE_ENDPOINT,
            'GET'
        );

        RestContext.request.addParameter(
            'contactId',
            String.valueOf(contactId)
        );

        ArchitectureDesignSiteNotificationApi.getApprovals();
    }

    /**
     * Converts a Lead.
     *
     * @param leadId Lead Id to convert.
     * @param convertedStatus Converted Lead status.
     * @return Lead conversion result.
     */
    private static Database.LeadConvertResult convertLead(
        Id leadId,
        String convertedStatus
    ) {
        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(leadId);
        conversion.setOwnerId(UserInfo.getUserId());
        conversion.setConvertedStatus(convertedStatus);

        return Database.convertLead(conversion);
    }

    /**
     * Returns the configured converted Lead status.
     *
     * @return Converted Lead status.
     */
    private static String getConvertedLeadStatus() {
        LeadStatus convertedLeadStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        return convertedLeadStatus.MasterLabel;
    }

    /**
     * Parses the REST response body.
     *
     * @return Response body as a map.
     */
    private static Map<String, Object> getResponseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    /**
     * Returns the data node from the REST response.
     *
     * @return Response data map.
     */
    private static Map<String, Object> getResponseData() {
        Map<String, Object> responseBody = getResponseBody();

        return (Map<String, Object>) responseBody.get('data');
    }

    /**
     * Verifies that an approved design cannot receive a second response.
     */
    @IsTest
    static void approveOnceOnly() {
        Architecture_Design__c design =
            createDesignFixture();

        Id contactId = getClientId(design);

        Test.startTest();

        submitDecision(
            design,
            contactId,
            STATUS_APPROVED,
            ''
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'The initial approval should succeed.'
        );

        submitDecision(
            design,
            contactId,
            STATUS_CHANGES_REQUESTED,
            'A second response'
        );

        System.assertEquals(
            409,
            RestContext.response.statusCode,
            'A second decision should be rejected.'
        );

        Test.stopTest();

        Architecture_Design__c savedDesign = [
            SELECT Status__c, Comments__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_APPROVED,
            savedDesign.Status__c,
            'The original approval status should remain unchanged.'
        );

        System.assertEquals(
            APPROVED_BY_CLIENT,
            savedDesign.Comments__c,
            'Default approval comments should be populated.'
        );
    }

    /**
     * Verifies comments are mandatory for change requests.
     */
    @IsTest
    static void changesRequireComments() {
        Architecture_Design__c design =
            createDesignFixture();

        Id contactId = getClientId(design);

        Test.startTest();

        submitDecision(
            design,
            contactId,
            STATUS_CHANGES_REQUESTED,
            '   '
        );

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Blank comments should not be accepted.'
        );

        submitDecision(
            design,
            contactId,
            STATUS_CHANGES_REQUESTED,
            '  Use lighter wood  '
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'A change request with comments should succeed.'
        );

        submitDecision(
            design,
            contactId,
            STATUS_APPROVED,
            ''
        );

        System.assertEquals(
            409,
            RestContext.response.statusCode,
            'A second decision should not be accepted.'
        );

        Test.stopTest();

        Architecture_Design__c savedDesign = [
            SELECT Comments__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Use lighter wood',
            savedDesign.Comments__c,
            'Leading and trailing spaces should be removed.'
        );
    }

    /**
     * Verifies an unrelated Contact cannot approve the design.
     */
    @IsTest
    static void unrelatedContactCannotRespondEvenWithMatchingEmail() {
        Architecture_Design__c design =
            createDesignFixture();

        Contact stranger = createContact(
            'Unrelated',
            'same@example.com'
        );

        Opportunity projectUpdate = new Opportunity(
            Id = design.Opportunity__c,
            Email__c = stranger.Email
        );

        update projectUpdate;

        Test.startTest();

        submitDecision(
            design,
            stranger.Id,
            STATUS_APPROVED,
            ''
        );

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'An unrelated Contact must not be authorized.'
        );

        Test.stopTest();

        Architecture_Design__c savedDesign = [
            SELECT Status__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_SENT,
            savedDesign.Status__c,
            'Unauthorized requests must not modify the design.'
        );
    }

    /**
     * Verifies file access requires both Contact ownership
     * and a valid ContentDocumentLink.
     */
    @IsTest
    static void filesRequireBothOwnershipAndDesignLink() {
        Architecture_Design__c design =
            createDesignFixture();

        Id contactId = getClientId(design);

        ContentVersion linkedVersion = new ContentVersion(
            Title = 'Design',
            PathOnClient = 'Design.pdf',
            VersionData = Blob.valueOf('test pdf'),
            FirstPublishLocationId = design.Id
        );

        insert linkedVersion;

        ContentVersion unrelatedVersion = new ContentVersion(
            Title = 'Other',
            PathOnClient = 'Other.pdf',
            VersionData = Blob.valueOf('other')
        );

        insert unrelatedVersion;

        Contact stranger = createContact(
            'Unrelated',
            null
        );

        Test.startTest();

        requestFile(
            design,
            contactId,
            linkedVersion.Id
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'A linked file should be available to the owning Contact.'
        );

        requestFile(
            design,
            contactId,
            unrelatedVersion.Id
        );

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'An unrelated file should not be returned.'
        );

        requestFile(
            design,
            stranger.Id,
            linkedVersion.Id
        );

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'An unrelated Contact should not access the design file.'
        );

        Test.stopTest();
    }

    /**
    * Verifies linked converted Leads expose all related projects.
    */
    @IsTest
    static void linkedConvertedProjectsAreAvailableAcrossContacts() {
        Lead firstLead = new Lead(
            LastName = 'First Project',
            Company = 'First Company',
            Email = 'first-project@example.com',
            Project_Request_Submitted__c = true,
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = STATUS_APPROVED
        );

        insert firstLead;

        Lead secondLead = new Lead(
            LastName = 'Second Project',
            Company = 'Second Company',
            Email = 'second-project@example.com',
            Portal_Account_Key__c = String.valueOf(firstLead.Id),
            Project_Request_Submitted__c = true,
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = STATUS_APPROVED
        );

        insert secondLead;

        String convertedStatus = getConvertedLeadStatus();

        Database.LeadConvertResult firstResult = convertLead(
            firstLead.Id,
            convertedStatus
        );

        Database.LeadConvertResult secondResult = convertLead(
            secondLead.Id,
            convertedStatus
        );

        System.assert(
            firstResult.isSuccess(),
            'The first Lead conversion should succeed.'
        );

        System.assert(
            secondResult.isSuccess(),
            'The second Lead conversion should succeed.'
        );

        Architecture_Design__c design = createArchitectureDesign(
            secondResult.getOpportunityId(),
            'Second project design'
        );

        Contact unrelatedContact = createContact(
            'Unrelated',
            null
        );

        Test.startTest();

        requestApprovals(
            firstResult.getContactId()
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'The linked Contact should receive the approvals response.'
        );

        Map<String, Object> data = getResponseData();

        List<Object> projects =
            (List<Object>) data.get('projects');

        List<Object> designs =
            (List<Object>) data.get('designs');

        System.assertEquals(
            2,
            projects.size(),
            'Both linked converted projects should be returned.'
        );

        System.assertEquals(
            1,
            designs.size(),
            'The linked design should be returned.'
        );

        submitDecision(
            design,
            unrelatedContact.Id,
            STATUS_APPROVED,
            ''
        );

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'An unrelated Contact should not approve the design.'
        );

        submitDecision(
            design,
            firstResult.getContactId(),
            STATUS_APPROVED,
            ''
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'A Contact from the linked Lead group should be authorized.'
        );

        Test.stopTest();
    }

    /**
     * Verifies the external design URL is returned by the API.
     */
    @IsTest
    static void returnsExternalDesignLink() {
        Architecture_Design__c design =
            createDesignFixture();

        Architecture_Design__c designUpdate =
            new Architecture_Design__c(
                Id = design.Id,
                External_File_Link__c = EXTERNAL_FILE_LINK
            );

        update designUpdate;

        Test.startTest();

        requestApprovals(
            getClientId(design)
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'The approvals request should succeed.'
        );

        Map<String, Object> data =
            getResponseData();

        List<Object> designs =
            (List<Object>) data.get('designs');

        Map<String, Object> designResponse =
            (Map<String, Object>) designs[0];

        System.assertEquals(
            EXTERNAL_FILE_LINK,
            designResponse.get('externalFileLink'),
            'The external design URL should be returned.'
        );
    }
}