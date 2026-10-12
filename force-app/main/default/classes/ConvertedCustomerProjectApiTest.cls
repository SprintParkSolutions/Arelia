/**
 * -----------------------------------------------------------------------------
 * Class Name      : ConvertedCustomerProjectApiTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for ConvertedCustomerProjectApi.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ConvertedCustomerProjectApiTest {

    private static final String BASE_ENDPOINT =
        '/services/apexrest/converted-customer/project/';

    private static final String SITE_VISITS_ENDPOINT =
        BASE_ENDPOINT + 'site-visits';

    private static final String PROJECT_NAME =
        'Arelia Test Interior Project';

    private static final String CONTACT_EMAIL =
        'converted.customer@example.com';

    private static final Integer HTTP_OK = 200;
    private static final Integer HTTP_BAD_REQUEST = 400;
    private static final Integer HTTP_NOT_FOUND = 404;

    
	/**
	* Creates common test records.
	*/
	@TestSetup
	static void setupData() {

		Account accountRecord = new Account(
			Name = 'Arelia Test Account'
		);
		insert accountRecord;

		Contact contactRecord = new Contact(
			FirstName = 'Test',
			LastName = 'Customer',
			AccountId = accountRecord.Id,
			Email = CONTACT_EMAIL,
			Phone = '9876543210'
		);
		insert contactRecord;

		Opportunity opportunityRecord = new Opportunity(
			Name = PROJECT_NAME,
			AccountId = accountRecord.Id,
			StageName = getOpportunityStage(),
			CloseDate = Date.today().addDays(30),
			Primary_Contact__c = contactRecord.Id,
			Lead_Name__c = 'Test Customer',
			Email__c = CONTACT_EMAIL,
			Budget__c = 500000,
			Estimated_Budget__c = 450000,
			Project_Description__c =
				'Interior design test project'
		);
		insert opportunityRecord;

		
		Lead leadRecord = new Lead(
			FirstName = 'Converted',
			LastName = 'Prospect',
			Company = 'Arelia Test Company',
			Email = 'conversion.test@example.com',
			Phone = '9876543210',
			Status = getOpenLeadStatus(),
			OwnerId = UserInfo.getUserId(),
			Appointment_Completed__c = true,
			Project_Request_Submitted__c = true
		);
		insert leadRecord;

		// Satisfy the Lead conversion validation rules.
		leadRecord.Site_Visit_Manager_Approval__c = true;
		leadRecord.Approval_Status__c = 'Approved';

		update leadRecord;

	}


    /**
     * Returns an available Opportunity stage.
     */
    private static String getOpportunityStage() {

        List<Schema.PicklistEntry> stages =
            Opportunity.StageName.getDescribe()
                .getPicklistValues();

        for (Schema.PicklistEntry stage : stages) {
            if (stage.isActive()) {
                return stage.getValue();
            }
        }

        return null;
    }

    /**
     * Returns an unconverted Lead status.
     */
    private static String getOpenLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'An open Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Returns a converted Lead status.
     */
    private static String getConvertedLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'A converted Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Initializes the REST request and response.
     */
    private static void prepareRequest(
        String endpoint,
        Id contactId,
        Id leadId,
        Id opportunityId
    ) {

        RestRequest request = new RestRequest();

        request.requestURI = endpoint;
        request.httpMethod = 'GET';

        if (contactId != null) {
            request.addParameter(
                'contactId',
                String.valueOf(contactId)
            );
        }

        if (leadId != null) {
            request.addParameter(
                'leadId',
                String.valueOf(leadId)
            );
        }

        if (opportunityId != null) {
            request.addParameter(
                'opportunityId',
                String.valueOf(opportunityId)
            );
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    /**
     * Executes the REST API and returns the JSON payload.
     */
    private static Map<String, Object> executeRequest() {

        ConvertedCustomerProjectApi.getProject();

        System.assertNotEquals(
            null,
            RestContext.response.responseBody,
            'REST response body must not be null.'
        );

        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    /**
     * Verifies the HTTP response status.
     */
    private static void assertStatus(Integer expectedStatus) {

        System.assertEquals(
            expectedStatus,
            RestContext.response.statusCode,
            'Unexpected HTTP response status.'
        );
    }

    /**
     * Gets the shared Opportunity.
     */
    private static Opportunity getOpportunityRecord() {

        return [
            SELECT Id, Name, Primary_Contact__c,
                Budget__c, Estimated_Budget__c
            FROM Opportunity
            WHERE Name = :PROJECT_NAME
            LIMIT 1
        ];
    }

    /**
     * Gets the shared Contact.
     */
    private static Contact getContactRecord() {

        return [
            SELECT Id
            FROM Contact
            WHERE Email = :CONTACT_EMAIL
            LIMIT 1
        ];
    }

    /**
     * Gets the test Lead.
     */
    private static Lead getLeadRecord() {

        return [
            SELECT Id, OwnerId
            FROM Lead
            WHERE Email = 'conversion.test@example.com'
            LIMIT 1
        ];
    }

    
	/**
	* Converts a Lead after validating approval requirements.
	*
	* @return Converted Lead with related Contact and Opportunity.
	*/
	private static Lead convertTestLead() {

		Lead sourceLead = [
			SELECT Id,
				OwnerId,
				Project_Request_Submitted__c,
				Site_Visit_Manager_Approval__c,
				Approval_Status__c
			FROM Lead
			WHERE Email = 'conversion.test@example.com'
			LIMIT 1
		];

		System.assertEquals(
			true,
			sourceLead.Project_Request_Submitted__c,
			'Project request must be submitted.'
		);

		System.assertEquals(
			true,
			sourceLead.Site_Visit_Manager_Approval__c,
			'Manager approval is required.'
		);

		System.assertEquals(
			'Approved',
			sourceLead.Approval_Status__c,
			'Approval Status must be Approved.'
		);

		Database.LeadConvert convertRequest =
			new Database.LeadConvert();

		convertRequest.setLeadId(sourceLead.Id);

		convertRequest.setConvertedStatus(
			getConvertedLeadStatus()
		);

		convertRequest.setOwnerId(
			UserInfo.getUserId()
		);

		convertRequest.setDoNotCreateOpportunity(false);

		convertRequest.setOpportunityName(
			'Converted Arelia Project'
		);

		Database.LeadConvertResult result =
			Database.convertLead(convertRequest);

		System.assertEquals(
			true,
			result.isSuccess(),
			'Lead conversion should succeed.'
		);

		System.assertNotEquals(
			null,
			result.getOpportunityId(),
			'Converted Opportunity ID should exist.'
		);

		System.assertNotEquals(
			null,
			result.getContactId(),
			'Converted Contact ID should exist.'
		);

		return [
			SELECT Id,
				IsConverted,
				ConvertedContactId,
				ConvertedOpportunityId
			FROM Lead
			WHERE Id = :sourceLead.Id
			LIMIT 1
		];
	}


    /**
     * Creates a Site Visit Report for an Opportunity.
     */
    private static Site_Visit_Report__c createSiteVisitReport(
        Id opportunityId
    ) {

        Site_Visit_Report__c reportRecord =
            new Site_Visit_Report__c(
                Opportunity__c = opportunityId,
                Description__c =
                    'Site visit inspection completed',
                Is_Final_Submitted__c = true,
                Management_Approval__c = true
            );

        insert reportRecord;

        return reportRecord;
    }

    /**
     * Tests successful retrieval by Opportunity ID.
     */
    @IsTest
    static void opportunityIdReturns200() {

        Opportunity opportunityRecord =
            getOpportunityRecord();

        prepareRequest(
            BASE_ENDPOINT,
            null,
            null,
            opportunityRecord.Id
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            true,
            result.get('projectSubmitted')
        );

        System.assertEquals(
            String.valueOf(opportunityRecord.Id),
            result.get('opportunityId')
        );

        System.assertEquals(
            PROJECT_NAME,
            result.get('projectName')
        );

        System.assertEquals(
            'Test Customer',
            result.get('firstName')
        );

        System.assertEquals(
            CONTACT_EMAIL,
            result.get('email')
        );

        System.assertEquals(
            Decimal.valueOf('500000'),
            result.get('customerBudget')
        );
    }

    /**
     * Tests Opportunity resolution through Contact.
     */
    @IsTest
    static void contactIdReturns200() {

        Contact contactRecord = getContactRecord();

        prepareRequest(
            BASE_ENDPOINT,
            contactRecord.Id,
            null,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            PROJECT_NAME,
            result.get('projectName')
        );
    }

    /**
     * Tests budget fallback to Estimated Budget.
     */
    @IsTest
    static void estimatedBudgetFallbackReturns200() {

        Opportunity opportunityRecord =
            getOpportunityRecord();

        opportunityRecord.Budget__c = null;
        update opportunityRecord;

        prepareRequest(
            BASE_ENDPOINT,
            null,
            null,
            opportunityRecord.Id
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            Decimal.valueOf('450000'),
            result.get('customerBudget')
        );
    }

    /**
     * Tests project details when optional fields are null.
     */
    @IsTest
    static void nullableProjectFieldsReturns200() {

        Opportunity opportunityRecord =
            getOpportunityRecord();

        opportunityRecord.Budget__c = null;
        opportunityRecord.Estimated_Budget__c = null;
        opportunityRecord.Project_Description__c = null;

        update opportunityRecord;

        prepareRequest(
            BASE_ENDPOINT,
            null,
            null,
            opportunityRecord.Id
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            null,
            result.get('customerBudget')
        );

        System.assertEquals(
            null,
            result.get('projectDescription')
        );
    }

    /**
     * Tests Site Visit response without reports.
     */
    @IsTest
    static void siteVisitWithoutReportsReturns200() {

        Opportunity opportunityRecord =
            getOpportunityRecord();

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            null,
            null,
            opportunityRecord.Id
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            false,
            result.get('reportAvailable')
        );

        System.assertEquals(
            null,
            result.get('report')
        );

        System.assertEquals(
            true,
            result.get('actionRequired')
        );

        System.assertEquals(
            false,
            result.get('appointmentConfirmed')
        );

        List<Object> reports =
            (List<Object>) result.get('reports');

        System.assertEquals(
            0,
            reports.size()
        );
    }

    /**
     * Tests Site Visit response with a linked report.
     */
    @IsTest
    static void siteVisitWithReportReturns200() {

        Opportunity opportunityRecord =
            getOpportunityRecord();

        Site_Visit_Report__c reportRecord =
            createSiteVisitReport(opportunityRecord.Id);

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            null,
            null,
            opportunityRecord.Id
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('reportAvailable')
        );

        List<Object> reports =
            (List<Object>) result.get('reports');

        System.assertEquals(
            1,
            reports.size()
        );

        Map<String, Object> firstReport =
            (Map<String, Object>) reports[0];

        System.assertEquals(
            String.valueOf(reportRecord.Id),
            firstReport.get('reportId')
        );

        System.assertEquals(
            true,
            firstReport.get('finalSubmitted')
        );

        System.assertEquals(
            true,
            firstReport.get('managementApproval')
        );

        System.assertEquals(
            'Site visit inspection completed',
            firstReport.get('description')
        );

        System.assertNotEquals(
            null,
            result.get('report')
        );
    }

    /**
     * Tests Site Visit resolution through Contact.
     */
    @IsTest
    static void contactSiteVisitReturns200() {

        Contact contactRecord = getContactRecord();

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            contactRecord.Id,
            null,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            false,
            result.get('reportAvailable')
        );
    }

    /**
     * Tests converted Lead project resolution.
     */
    @IsTest
    static void convertedLeadProjectReturns200() {

        Lead convertedLead = convertTestLead();

        prepareRequest(
            BASE_ENDPOINT,
            null,
            convertedLead.Id,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            String.valueOf(
                convertedLead.ConvertedOpportunityId
            ),
            result.get('opportunityId')
        );
    }

    /**
     * Tests converted Contact project resolution.
     */
    @IsTest
    static void convertedContactProjectReturns200() {

        Lead convertedLead = convertTestLead();

        prepareRequest(
            BASE_ENDPOINT,
            convertedLead.ConvertedContactId,
            null,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            String.valueOf(
                convertedLead.ConvertedOpportunityId
            ),
            result.get('opportunityId')
        );
    }

    /**
     * Tests Site Visit lookup using converted Lead.
     */
    @IsTest
    static void convertedLeadSiteVisitReturns200() {

        Lead convertedLead = convertTestLead();

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            null,
            convertedLead.Id,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            String.valueOf(convertedLead.Id),
            result.get('leadId')
        );

        System.assertEquals(
            String.valueOf(
                convertedLead.ConvertedOpportunityId
            ),
            result.get('opportunityId')
        );
    }

    /**
     * Tests Site Visit resolution with a converted
     * Opportunity ID.
     */
    @IsTest
    static void convertedOpportunitySiteVisitReturns200() {

        Lead convertedLead = convertTestLead();

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            null,
            null,
            convertedLead.ConvertedOpportunityId
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            String.valueOf(convertedLead.Id),
            result.get('leadId')
        );
    }

    /**
     * Tests Site Visit report associated with
     * a converted Opportunity.
     */
    @IsTest
    static void convertedLeadWithReportReturns200() {

        Lead convertedLead = convertTestLead();

        Site_Visit_Report__c reportRecord =
            createSiteVisitReport(
                convertedLead.ConvertedOpportunityId
            );

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            null,
            convertedLead.Id,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('reportAvailable')
        );

        List<Object> reports =
            (List<Object>) result.get('reports');

        System.assertEquals(
            1,
            reports.size()
        );

        Map<String, Object> reportPayload =
            (Map<String, Object>) reports[0];

        System.assertEquals(
            String.valueOf(reportRecord.Id),
            reportPayload.get('reportId')
        );
    }

    /**
     * Tests an unconverted Lead with no Opportunity.
     */
    @IsTest
    static void unconvertedLeadReturns404() {

        Lead leadRecord = getLeadRecord();

        prepareRequest(
            BASE_ENDPOINT,
            null,
            leadRecord.Id,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_NOT_FOUND);

        System.assertEquals(
            false,
            result.get('success')
        );
    }

    /**
     * Tests request without any identifiers.
     */
    @IsTest
    static void missingIdentifiersReturns404() {

        prepareRequest(
            BASE_ENDPOINT,
            null,
            null,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_NOT_FOUND);

        System.assertEquals(
            false,
            result.get('success')
        );

        System.assertEquals(
            'No Opportunity is associated with this Contact or Lead.',
            result.get('message')
        );
    }

    /**
     * Tests unsupported identifier prefixes.
     */
    @IsTest
    static void incorrectIdPrefixesReturns404() {

        Opportunity opportunityRecord =
            getOpportunityRecord();

        prepareRequest(
            BASE_ENDPOINT,
            null,
            null,
            null
        );

        RestContext.request.addParameter(
            'contactId',
            String.valueOf(opportunityRecord.Id)
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_NOT_FOUND);

        System.assertEquals(
            false,
            result.get('success')
        );
    }

    /**
     * Tests malformed ID handling.
     */
    @IsTest
    static void malformedOpportunityIdReturns400() {

        prepareRequest(
            BASE_ENDPOINT,
            null,
            null,
            null
        );

        RestContext.request.addParameter(
            'opportunityId',
            '006InvalidIdValue'
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_BAD_REQUEST);

        System.assertEquals(
            false,
            result.get('success')
        );

        System.assertNotEquals(
            null,
            result.get('message')
        );
    }

    /**
     * Tests valid Contact with no matching Opportunity.
     */
    @IsTest
    static void unrelatedContactReturns404() {

        Contact unrelatedContact = new Contact(
            LastName = 'Unrelated Customer',
            Email = 'unrelated@example.com'
        );
        insert unrelatedContact;

        prepareRequest(
            BASE_ENDPOINT,
            unrelatedContact.Id,
            null,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_NOT_FOUND);

        System.assertEquals(
            false,
            result.get('success')
        );
    }

    /**
     * Tests valid Lead and Contact together.
     * Exercises Lead-only report query context.
     */
    @IsTest
    static void unconvertedLeadWithContactSiteVisitReturns200() {

        Lead leadRecord = getLeadRecord();
        Contact contactRecord = getContactRecord();

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            contactRecord.Id,
            leadRecord.Id,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            String.valueOf(leadRecord.Id),
            result.get('leadId')
        );

        System.assertEquals(
            false,
            result.get('reportAvailable')
        );
    }

    /**
     * Tests project response when both Contact
     * and Opportunity IDs are supplied.
     */
    @IsTest
    static void contactAndOpportunityReturns200() {

        Contact contactRecord = getContactRecord();

        Opportunity opportunityRecord =
            getOpportunityRecord();

        prepareRequest(
            BASE_ENDPOINT,
            contactRecord.Id,
            null,
            opportunityRecord.Id
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_OK);

        System.assertEquals(
            true,
            result.get('success')
        );

        System.assertEquals(
            String.valueOf(opportunityRecord.Id),
            result.get('opportunityId')
        );
    }

    /**
     * Tests missing identifiers on Site Visit endpoint.
     */
    @IsTest
    static void missingSiteVisitIdentifiersReturns404() {

        prepareRequest(
            SITE_VISITS_ENDPOINT,
            null,
            null,
            null
        );

        Test.startTest();
        Map<String, Object> result = executeRequest();
        Test.stopTest();

        assertStatus(HTTP_NOT_FOUND);

        System.assertEquals(
            false,
            result.get('success')
        );
    }
}