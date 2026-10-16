/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProspectSiteVisitRestControllerTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : Test class for ProspectSiteVisitRestController.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProspectSiteVisitRestControllerTest {

    private static final String ENDPOINT =
        '/services/apexrest/registration/lead/site-visit';

    private static final String STATUS_PENDING =
        'Pending';

    private static final String STATUS_APPROVED =
        'Approved';

    private static final String STATUS_RESCHEDULED =
        'Rescheduled';

    private static final String STATUS_APPOINTMENT_RESCHEDULED =
        'Appointment Rescheduled';

    private static final String TIME_SLOT =
        '10AM-11AM';

    private static final String REQUESTED_TIME_SLOT =
        '2PM-3PM';

    private static final String SITE_LOCATION =
        'Hyderabad';

    /**
     * Creates the base Lead used by the tests.
     *
     * @param suffix unique suffix for test data
     * @return inserted Lead record
     */
    private static Lead createLead(String suffix) {
        Lead leadRecord = new Lead(
            FirstName = 'Site',
            LastName = 'Visit ' + suffix,
            Company = 'Arelia Test ' + suffix,
            Email =
                'sitevisit.'
                + suffix
                + '@example.com',
            Phone = '9876543210'
        );

        insert leadRecord;

        return leadRecord;
    }

	/**
	* Creates a test Supervisor User.
	*
	* @param suffix unique suffix for the User
	* @return inserted Supervisor User
	*/
	private static User createSupervisorUser(
		String suffix
	) {
		Profile standardProfile = [
			SELECT Id
			FROM Profile
			WHERE Name = 'Standard User'
			LIMIT 1
		];

		String uniqueValue =
			String.valueOf(DateTime.now().getTime());

		User supervisorUser = new User(
			FirstName = 'Site',
			LastName = 'Supervisor ' + suffix,
			Alias = 'sv' + suffix.left(3),
			Email =
				'supervisor.'
				+ uniqueValue
				+ '@example.com',
			Username =
				'supervisor.'
				+ uniqueValue
				+ '.'
				+ suffix
				+ '@example.com',
			CommunityNickname =
				'supervisor'
				+ uniqueValue,
			ProfileId =
				standardProfile.Id,
			TimeZoneSidKey =
				'Asia/Kolkata',
			LocaleSidKey =
				'en_US',
			EmailEncodingKey =
				'UTF-8',
			LanguageLocaleKey =
				'en_US'
		);

		insert supervisorUser;

		return supervisorUser;
	}

    /**
	* Creates a Lead with a valid Pending appointment
	* and assigned Supervisor.
	*
	* @param suffix unique suffix for test data
	* @return Lead with Pending appointment
	*/
	private static Lead createPendingAppointment(
		String suffix
	) {
		User supervisorUser = createSupervisorUser(suffix);
		Lead leadRecord = createLead(suffix);
		leadRecord.Project_Request_Submitted__c = true;
		leadRecord.Approval_Status__c = 'Approved';
		leadRecord.Supervisor_User__c = supervisorUser.Id;
		leadRecord.Appointment_Sent_date__c = Date.today();
		leadRecord.Appointment_Date__c = Date.today().addDays(5);
		leadRecord.Appointment_Time_Slots__c = TIME_SLOT;
		leadRecord.Appointment_Status__c = STATUS_PENDING;
		leadRecord.Site_Location__c = SITE_LOCATION;
		update leadRecord;
		return leadRecord;
	}

    /**
     * Configures the REST request and response.
     *
     * @param leadId Lead Id request parameter
     */
    private static void configureRestContext(
        String leadId
    ) {
        RestRequest requestValue =
            new RestRequest();

        requestValue.requestUri =
            ENDPOINT;

        requestValue.httpMethod =
            'GET';

        if (leadId != null) {
            requestValue.addParameter(
                'leadId',
                leadId
            );
        }

        RestContext.request =
            requestValue;

        RestContext.response =
            new RestResponse();
    }

    /**
     * Executes the REST endpoint.
     *
     * @param leadId Lead Id request parameter
     * @return REST response DTO
     */
    private static ProspectSiteVisitRestController.SiteVisitResponse
        executeRequest(String leadId) {

        configureRestContext(leadId);

        return ProspectSiteVisitRestController.getSiteVisit();
    }

    /**
     * Verifies behavior when Lead Id is missing.
     */
    @IsTest
    static void missingLeadIdReturns400() {
        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest(null);

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing Lead Id should return HTTP 400.'
        );

        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            false,
            response.appointmentAvailable,
            'Appointment should not be available.'
        );

        System.assertEquals(
            'Salesforce Lead ID is required.',
            response.message,
            'Unexpected validation message.'
        );
    }

    /**
     * Verifies behavior when Lead Id is blank.
     */
    @IsTest
    static void blankLeadIdReturns400() {
        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest('   ');

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Blank Lead Id should return HTTP 400.'
        );

        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            'Salesforce Lead ID is required.',
            response.message,
            'Unexpected validation message.'
        );
    }

    /**
     * Verifies behavior for an invalid Salesforce Id.
     */
    @IsTest
    static void invalidLeadIdReturns400() {
        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest('INVALID_ID');

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid Lead Id should return HTTP 400.'
        );

        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            false,
            response.appointmentAvailable,
            'Appointment should not be available.'
        );

        System.assertEquals(
            'Invalid Salesforce Lead ID.',
            response.message,
            'Unexpected validation message.'
        );
    }

    /**
     * Verifies behavior when a Salesforce Id
     * is valid but is not a Lead Id.
     */
    @IsTest
    static void nonLeadIdReturns400() {
        Account accountRecord =
            new Account(
                Name = 'Site Visit Test Account'
            );

        insert accountRecord;

        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest(
                    String.valueOf(accountRecord.Id)
                );

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Non-Lead Id should return HTTP 400.'
        );

        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            'Invalid Salesforce Lead ID.',
            response.message,
            'Unexpected validation message.'
        );
    }

    /**
     * Verifies behavior when the Lead has been deleted.
     */
    @IsTest
    static void deletedLeadReturns404() {
        Lead leadRecord =
            createLead('Deleted');

        Id deletedLeadId =
            leadRecord.Id;

        delete leadRecord;

        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest(
                    String.valueOf(deletedLeadId)
                );

        Test.stopTest();

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'Deleted Lead should return HTTP 404.'
        );

        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            false,
            response.appointmentAvailable,
            'Appointment should not be available.'
        );

        System.assertEquals(
            'Lead record was not found.',
            response.message,
            'Unexpected response message.'
        );
    }

    /**
     * Verifies Pending site visit details.
     */
    @IsTest
    static void pendingAppointmentRequiresAction() {
        Lead leadRecord =
            createPendingAppointment('Pending');

        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest(
                    String.valueOf(leadRecord.Id)
                );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Pending appointment should return HTTP 200.'
        );

        System.assertEquals(
            true,
            response.success,
            'Request should succeed.'
        );

        System.assertEquals(
            true,
            response.appointmentAvailable,
            'Appointment should be available.'
        );

        System.assertEquals(
            true,
            response.actionRequired,
            'Pending appointment should require action.'
        );

        System.assertEquals(
            STATUS_PENDING,
            response.appointmentStatus,
            'Appointment status is incorrect.'
        );

        System.assertEquals(
            TIME_SLOT,
            response.appointmentTimeSlot,
            'Appointment time slot is incorrect.'
        );

        System.assertEquals(
            String.valueOf(
                Date.today().addDays(5)
            ),
            response.appointmentDate,
            'Appointment date is incorrect.'
        );

        System.assertEquals(
            SITE_LOCATION,
            response.siteLocation,
            'Site location is incorrect.'
        );

        System.assertEquals(
            false,
            response.appointmentConfirmed,
            'Pending appointment should not be confirmed.'
        );

        System.assertEquals(
            null,
            response.clientResponseMessage,
            'Pending status should have no client response message.'
        );

        System.assertEquals(
            9,
            response.availableTimeSlots.size(),
            'Nine available time slots should be returned.'
        );

        System.assertEquals(
            '9AM-10AM',
            response.availableTimeSlots[0],
            'First time slot is incorrect.'
        );

        System.assertEquals(
            '5PM-6PM',
            response.availableTimeSlots[8],
            'Last time slot is incorrect.'
        );

        System.assertEquals(
            'Site visit appointment details loaded successfully.',
            response.message,
            'Unexpected response message.'
        );
    }

    /**
     * Verifies Appointment Rescheduled status.
     */
    @IsTest
    static void appointmentRescheduledRequiresAction() {
        Lead leadRecord =
            createPendingAppointment(
                'AppointmentRescheduled'
            );

        Date requestedDate =
            Date.today().addDays(8);

        leadRecord.Appointment_Status__c =
            STATUS_APPOINTMENT_RESCHEDULED;

        leadRecord.Appointment_Rescheduled_Time__c =
            requestedDate;

        leadRecord.Time_Slots__c =
            REQUESTED_TIME_SLOT;

        update leadRecord;

        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest(
                    String.valueOf(leadRecord.Id)
                );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Appointment Rescheduled should return HTTP 200.'
        );

        System.assertEquals(
            true,
            response.success,
            'Request should succeed.'
        );

        System.assertEquals(
            true,
            response.appointmentAvailable,
            'Appointment should be available.'
        );

        System.assertEquals(
            true,
            response.actionRequired,
            'Appointment Rescheduled should require action.'
        );

        System.assertEquals(
            STATUS_APPOINTMENT_RESCHEDULED,
            response.appointmentStatus,
            'Appointment status is incorrect.'
        );

        System.assertEquals(
            String.valueOf(requestedDate),
            response.requestedDate,
            'Requested date is incorrect.'
        );

        System.assertEquals(
            REQUESTED_TIME_SLOT,
            response.requestedTimeSlot,
            'Requested time slot is incorrect.'
        );

        System.assertEquals(
            null,
            response.clientResponseMessage,
            'Appointment Rescheduled should not have '
                + 'a final client response message.'
        );
    }

    /**
     * Verifies an Approved site visit appointment.
     */
    @IsTest
    static void approvedAppointmentReturnsClientMessage() {
        Lead leadRecord =
            createPendingAppointment('Approved');

        leadRecord.Appointment_Status__c =
            STATUS_APPROVED;

        update leadRecord;

        Test.startTest();

        ProspectSiteVisitRestController.SiteVisitResponse
            response =
                executeRequest(
                    String.valueOf(leadRecord.Id)
                );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Approved appointment should return HTTP 200.'
        );

        System.assertEquals(
            true,
            response.success,
            'Request should succeed.'
        );

        System.assertEquals(
            true,
            response.appointmentAvailable,
            'Appointment should be available.'
        );

        System.assertEquals(
            false,
            response.actionRequired,
            'Approved appointment should not require action.'
        );

        System.assertEquals(
            STATUS_APPROVED,
            response.appointmentStatus,
            'Appointment status is incorrect.'
        );

        System.assertEquals(
            'You approved this site visit appointment.',
            response.clientResponseMessage,
            'Approved response message is incorrect.'
        );
    }

    /**
     * Verifies a client Rescheduled response.
     */
    @IsTest
	static void rescheduledAppointmentReturnsClientMessage() {
		Lead leadRecord =
			createPendingAppointment('Rescheduled');

		Date requestedDate =
			Date.today().addDays(10);

		leadRecord.Appointment_Rescheduled_Time__c =
			requestedDate;

		leadRecord.Time_Slots__c =
			REQUESTED_TIME_SLOT;

		leadRecord.Appointment_Status__c =
			STATUS_RESCHEDULED;

		update leadRecord;

		Test.startTest();

		ProspectSiteVisitRestController.SiteVisitResponse
			response =
				executeRequest(
					String.valueOf(leadRecord.Id)
				);

		Test.stopTest();

		System.assertEquals(
			200,
			RestContext.response.statusCode,
			'Rescheduled appointment should return HTTP 200.'
		);

		System.assertEquals(
			true,
			response.success,
			'Request should succeed.'
		);

		System.assertEquals(
			true,
			response.appointmentAvailable,
			'Appointment should be available.'
		);

		System.assertEquals(
			false,
			response.actionRequired,
			'Rescheduled status should not require action.'
		);

		System.assertEquals(
			STATUS_RESCHEDULED,
			response.appointmentStatus,
			'Appointment status is incorrect.'
		);

		System.assertEquals(
			String.valueOf(requestedDate),
			response.requestedDate,
			'Requested date is incorrect.'
		);

		System.assertEquals(
			REQUESTED_TIME_SLOT,
			response.requestedTimeSlot,
			'Requested time slot is incorrect.'
		);

		System.assertEquals(
			'You requested a different site visit date and time.',
			response.clientResponseMessage,
			'Rescheduled response message is incorrect.'
		);

		System.assertNotEquals(
			null,
			response.supervisorName,
			'Supervisor name should be returned.'
		);
	}

    /**
     * Verifies the response DTO default values.
     */
    @IsTest
    static void responseConstructorSetsDefaults() {
        ProspectSiteVisitRestController.SiteVisitResponse
            response = new ProspectSiteVisitRestController.SiteVisitResponse();

        System.assertEquals(
            false,
            response.success,
            'Success should default to false.'
        );

        System.assertEquals(
            false,
            response.appointmentAvailable,
            'Appointment availability should default to false.'
        );

        System.assertEquals(
            false,
            response.actionRequired,
            'Action required should default to false.'
        );

        System.assertEquals(
            false,
            response.appointmentConfirmed,
            'Appointment confirmed should default to false.'
        );

        System.assertNotEquals(
            null,
            response.availableTimeSlots,
            'Available time slots should be initialized.'
        );

        System.assertEquals(
            0,
            response.availableTimeSlots.size(),
            'Default time-slot list should be empty.'
        );
    }
}