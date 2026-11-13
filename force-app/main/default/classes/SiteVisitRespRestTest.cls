/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : SiteVisitRespRestTest
 * Author          : Arelia
 * Created Date    : Oct 7, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 7, 2026
 * Description     : This test class is for ProspectSiteVisitResponseRestController
 */

@IsTest
private class SiteVisitRespRestTest {

    private static final String ENDPOINT = '/services/apexrest/registration/lead/site-visit/response';
    private static final String HTTP_POST = 'POST';
    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_RESCHEDULED = 'Rescheduled';
    private static final String STATUS_APPOINTMENT_RESCHEDULED = 'Appointment Rescheduled';
    private static final String RESPONSE_APPROVED = 'Approved';
    private static final String RESPONSE_RESCHEDULE_REQUESTED = 'Reschedule Requested';
    private static final String RESPONSE_RESCHEDULED = 'Rescheduled';
    private static final String DEFAULT_TIME_SLOT = '10AM-11AM';
    private static final String RESCHEDULE_TIME_SLOT = '2PM-3PM';
    private static final String TEST_PHONE = '9876543210';
    private static final String SUPERVISOR_ALIAS = 'tspv';

    /**
     * Creates the Supervisor User separately from Lead data
     * to avoid Mixed DML errors.
     */
    @TestSetup
    static void setupSupervisor() {

        Profile profileRecord = [
            SELECT Id
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];

        String uniqueValue =
            String.valueOf(
                DateTime.now().getTime()
            );

        User supervisorUser = new User(
            FirstName = 'Test',
            LastName = 'Supervisor',
            Alias = SUPERVISOR_ALIAS,
            Email =
                'sitevisit.supervisor.'
                + uniqueValue
                + '@example.com',
            Username =
                'sitevisit.supervisor.'
                + uniqueValue
                + '@example.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id
        );

        insert supervisorUser;
    }

    /**
     * Verifies successful approval of a pending appointment.
     */
    @IsTest
    static void approveAppointmentReturnsSuccess() {

        Lead leadRecord = createAppointmentLead(
            'Approval Client',
            STATUS_PENDING
        );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_APPROVED,
                null,
                null
            )
        );

        Test.startTest();

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            ProspectSiteVisitResponseRestController.submitResponse();

        Test.stopTest();

        Lead updatedLead =
            getLead(
                leadRecord.Id
            );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Approval should return HTTP 200.'
        );

        System.assertEquals(
            true,
            result.success,
            'Approval should succeed.'
        );

        System.assertEquals(
            leadRecord.Id,
            result.leadId,
            'Response should contain the Lead Id.'
        );

        System.assertEquals(
            STATUS_APPROVED,
            result.appointmentStatus,
            'Appointment should become Approved.'
        );

        System.assertEquals(
            true,
            result.appointmentConfirmed,
            'Appointment should be confirmed.'
        );

        System.assertEquals(
            STATUS_APPROVED,
            updatedLead.Appointment_Status__c,
            'Stored appointment status should be Approved.'
        );

        System.assertEquals(
            true,
            updatedLead.Appointment_Completed__c,
            'Appointment Completed should be checked.'
        );

        System.assertEquals(
            Date.today().addDays(5),
            updatedLead.Appointment_Date__c,
            'Original appointment date should remain.'
        );

        System.assertEquals(
            DEFAULT_TIME_SLOT,
            updatedLead.Appointment_Time_Slots__c,
            'Original time slot should remain.'
        );

        System.assertEquals(
            null,
            updatedLead.Appointment_Rescheduled_Time__c,
            'Rescheduled date should be cleared.'
        );

        System.assertEquals(
            null,
            updatedLead.Time_Slots__c,
            'Rescheduled time should be cleared.'
        );
    }

    /**
     * Verifies successful reschedule request.
     */
    @IsTest
    static void rescheduleAppointmentReturnsSuccess() {

        Lead leadRecord = createAppointmentLead(
            'Reschedule Client',
            STATUS_PENDING
        );

        Date requestedDate =
            Date.today().addDays(10);

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULE_REQUESTED,
                String.valueOf(requestedDate),
                RESCHEDULE_TIME_SLOT
            )
        );

        Test.startTest();

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            ProspectSiteVisitResponseRestController.submitResponse();

        Test.stopTest();

        Lead updatedLead =
            getLead(
                leadRecord.Id
            );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Reschedule request should return HTTP 200.'
        );

        System.assertEquals(
            true,
            result.success,
            'Reschedule request should succeed.'
        );

        System.assertEquals(
            STATUS_RESCHEDULED,
            result.appointmentStatus,
            'Status should become Rescheduled.'
        );

        System.assertEquals(
            true,
            result.appointmentConfirmed,
            'Appointment Completed should be true.'
        );

        System.assertEquals(
            String.valueOf(requestedDate),
            result.requestedDate,
            'Requested date should be returned.'
        );

        System.assertEquals(
            RESCHEDULE_TIME_SLOT,
            result.requestedTimeSlot,
            'Requested time slot should be returned.'
        );

        System.assertEquals(
            null,
            updatedLead.Appointment_Date__c,
            'Original appointment date should be cleared.'
        );

        System.assertEquals(
            null,
            updatedLead.Appointment_Time_Slots__c,
            'Original appointment time should be cleared.'
        );

        System.assertEquals(
            requestedDate,
            updatedLead.Appointment_Rescheduled_Time__c,
            'Requested date should be saved.'
        );

        System.assertEquals(
            RESCHEDULE_TIME_SLOT,
            updatedLead.Time_Slots__c,
            'Requested time should be saved.'
        );
    }

    /**
     * Verifies that Rescheduled is also an accepted request value.
     */
    @IsTest
    static void rescheduledValueReturnsSuccess() {

        Lead leadRecord = createAppointmentLead(
            'Alternate Reschedule Client',
            STATUS_PENDING
        );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULED,
                String.valueOf(
                    Date.today().addDays(7)
                ),
                '3PM-4PM'
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Rescheduled should return HTTP 200.'
        );

        System.assertEquals(
            true,
            result.success,
            'Rescheduled response should succeed.'
        );

        System.assertEquals(
            STATUS_RESCHEDULED,
            result.appointmentStatus,
            'Appointment should become Rescheduled.'
        );
    }

    /**
     * Verifies approval after the Supervisor reschedules
     * an appointment.
     */
    @IsTest
    static void appointmentRescheduledAllowsApproval() {

        Lead leadRecord = createAppointmentLead(
            'Supervisor Rescheduled Client',
            STATUS_APPOINTMENT_RESCHEDULED
        );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_APPROVED,
                null,
                null
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Appointment Rescheduled should allow approval.'
        );

        System.assertEquals(
            true,
            result.success,
            'Approval should succeed.'
        );

        System.assertEquals(
            STATUS_APPROVED,
            result.appointmentStatus,
            'Final status should be Approved.'
        );
    }

    /**
     * Verifies case-insensitive Approved response.
     */
    @IsTest
    static void lowercaseApprovedReturnsSuccess() {

        Lead leadRecord = createAppointmentLead(
            'Lowercase Approval Client',
            STATUS_PENDING
        );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                'approved',
                null,
                null
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Lowercase approved should return HTTP 200.'
        );

        System.assertEquals(
            true,
            result.success,
            'Case-insensitive approval should succeed.'
        );
    }

    /**
     * Verifies empty request body validation.
     */
    @IsTest
    static void missingRequestBodyReturns400() {

        prepareRequestWithoutBody();

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing request body should return HTTP 400.'
        );

        System.assertEquals(
            false,
            result.success,
            'Request should fail.'
        );

        System.assertEquals(
            'Request body is required.',
            result.message,
            'Unexpected missing-body message.'
        );
    }

    /**
     * Verifies malformed JSON handling.
     */
    @IsTest
    static void malformedJsonReturns400() {

        prepareRawRequest(
            '{"leadId":'
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Malformed JSON should return HTTP 400.'
        );

        System.assertEquals(
            false,
            result.success,
            'Malformed JSON should fail.'
        );

        System.assertEquals(
            'Invalid request format.',
            result.message,
            'Unexpected malformed JSON message.'
        );
    }

    /**
     * Verifies missing Lead Id validation.
     */
    @IsTest
    static void missingLeadIdReturns400() {

        Map<String, Object> payload =
            new Map<String, Object>{
                'response' => RESPONSE_APPROVED
            };

        prepareJsonRequest(
            payload
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing Lead Id should return HTTP 400.'
        );

        System.assertEquals(
            false,
            result.success,
            'Request should fail.'
        );

        System.assertEquals(
            'Salesforce Lead ID is required.',
            result.message,
            'Unexpected Lead Id validation message.'
        );
    }

    /**
     * Verifies invalid Lead Id validation.
     */
    @IsTest
    static void invalidLeadIdReturns400() {

        Map<String, Object> payload =
            new Map<String, Object>{
                'leadId' => 'INVALID',
                'response' => RESPONSE_APPROVED
            };

        prepareJsonRequest(
            payload
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid Lead Id should return HTTP 400.'
        );

        System.assertEquals(
            false,
            result.success,
            'Invalid Lead Id should fail.'
        );

        System.assertEquals(
            'Invalid Salesforce Lead ID.',
            result.message,
            'Unexpected invalid Lead Id message.'
        );
    }

    /**
     * Verifies that a Salesforce Id belonging to another
     * object is rejected.
     */
    @IsTest
    static void nonLeadSalesforceIdReturns400() {

        Account accountRecord =
            new Account(
                Name = 'Site Visit Test Account'
            );

        insert accountRecord;

        Map<String, Object> payload =
            new Map<String, Object>{
                'leadId' => accountRecord.Id,
                'response' => RESPONSE_APPROVED
            };

        prepareJsonRequest(
            payload
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Account Id should return HTTP 400.'
        );

        System.assertEquals(
            'Invalid Salesforce Lead ID.',
            result.message,
            'Non-Lead Salesforce Id should be rejected.'
        );
    }

    /**
     * Verifies Lead not found scenario using a valid deleted Lead Id.
     */
    @IsTest
    static void deletedLeadReturns404() {

        Lead leadRecord =
            createAppointmentLead(
                'Deleted Lead Client',
                STATUS_PENDING
            );

        Id deletedLeadId =
            leadRecord.Id;

        delete leadRecord;

        prepareJsonRequest(
            createPayload(
                deletedLeadId,
                RESPONSE_APPROVED,
                null,
                null
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'Deleted Lead should return HTTP 404.'
        );

        System.assertEquals(
            false,
            result.success,
            'Deleted Lead request should fail.'
        );

        System.assertEquals(
            'Lead record was not found.',
            result.message,
            'Unexpected Lead not found message.'
        );
    }

    /**
     * Verifies missing response validation.
     */
    @IsTest
    static void missingResponseReturns400() {

        Lead leadRecord =
            createAppointmentLead(
                'Missing Response Client',
                STATUS_PENDING
            );

        Map<String, Object> payload =
            new Map<String, Object>{
                'leadId' => leadRecord.Id
            };

        prepareJsonRequest(
            payload
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing response should return HTTP 400.'
        );

        System.assertEquals(
            'Appointment response is required.',
            result.message,
            'Unexpected missing response message.'
        );
    }

    /**
     * Verifies appointment availability validation.
     */
    @IsTest
    static void noAppointmentReturns409() {

        Lead leadRecord =
            createLead(
                'No Appointment Client'
            );

        leadRecord.Appointment_Status__c =
            STATUS_PENDING;

        update leadRecord;

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_APPROVED,
                null,
                null
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            409,
            RestContext.response.statusCode,
            'No appointment should return HTTP 409.'
        );

        System.assertEquals(
            false,
            result.success,
            'Request should fail.'
        );

        System.assertEquals(
            'No site visit appointment is available for response.',
            result.message,
            'Unexpected no-appointment message.'
        );

        System.assertEquals(
            leadRecord.Id,
            result.leadId,
            'Lead Id should be returned.'
        );
    }

    /**
	* Verifies already-approved appointment handling.
	*/
	@IsTest
	static void alreadyApprovedReturns409() {

		Lead leadRecord =
			createAppointmentLead(
				'Already Approved Client',
				STATUS_PENDING
			);

		/*
		* First request performs the real approval.
		*/
		prepareJsonRequest(
			createPayload(
				leadRecord.Id,
				RESPONSE_APPROVED,
				null,
				null
			)
		);

		ProspectSiteVisitResponseRestController.ResponseWrapper
			initialResult =
				ProspectSiteVisitResponseRestController.submitResponse();

		System.assertEquals(
			true,
			initialResult.success,
			'Initial approval should succeed.'
		);

		System.assertEquals(
			STATUS_APPROVED,
			initialResult.appointmentStatus,
			'Initial request should approve the appointment.'
		);

		/*
		* Second request should be rejected because the
		* appointment has already been approved.
		*/
		prepareJsonRequest(
			createPayload(
				leadRecord.Id,
				RESPONSE_APPROVED,
				null,
				null
			)
		);

		Test.startTest();

		ProspectSiteVisitResponseRestController.ResponseWrapper result =
			ProspectSiteVisitResponseRestController.submitResponse();

		Test.stopTest();

		System.assertEquals(
			409,
			RestContext.response.statusCode,
			'Already-approved appointment should return HTTP 409.'
		);

		System.assertEquals(
			false,
			result.success,
			'Second approval request should fail.'
		);

		System.assertEquals(
			'You have already approved this appointment.',
			result.message,
			'Unexpected already-approved message.'
		);

		System.assertEquals(
			STATUS_APPROVED,
			result.appointmentStatus,
			'Existing Approved status should be returned.'
		);
	}

    /**
	* Verifies already-rescheduled appointment handling.
	*/
	@IsTest
	static void alreadyRescheduledReturns409() {

		Lead leadRecord =
			createAppointmentLead(
				'Already Rescheduled Client',
				STATUS_PENDING
			);

		Date requestedDate =
			Date.today().addDays(7);

		/*
		* First request performs the real reschedule.
		*/
		prepareJsonRequest(
			createPayload(
				leadRecord.Id,
				RESPONSE_RESCHEDULE_REQUESTED,
				String.valueOf(requestedDate),
				RESCHEDULE_TIME_SLOT
			)
		);

		ProspectSiteVisitResponseRestController.ResponseWrapper
			initialResult =
				ProspectSiteVisitResponseRestController.submitResponse();

		System.assertEquals(
			true,
			initialResult.success,
			'Initial reschedule request should succeed.'
		);

		System.assertEquals(
			STATUS_RESCHEDULED,
			initialResult.appointmentStatus,
			'Initial request should reschedule the appointment.'
		);

		/*
		* Second request should be rejected because a
		* reschedule request was already submitted.
		*/
		prepareJsonRequest(
			createPayload(
				leadRecord.Id,
				RESPONSE_APPROVED,
				null,
				null
			)
		);

		Test.startTest();

		ProspectSiteVisitResponseRestController.ResponseWrapper result =
			ProspectSiteVisitResponseRestController.submitResponse();

		Test.stopTest();

		System.assertEquals(
			409,
			RestContext.response.statusCode,
			'Already-rescheduled appointment should return HTTP 409.'
		);

		System.assertEquals(
			false,
			result.success,
			'Second response should fail.'
		);

		System.assertEquals(
			'You have already requested a new date and time.',
			result.message,
			'Unexpected already-rescheduled message.'
		);

		System.assertEquals(
			STATUS_RESCHEDULED,
			result.appointmentStatus,
			'Existing Rescheduled status should be returned.'
		);
	}

    /**
     * Verifies invalid appointment response.
     */
    @IsTest
    static void invalidResponseReturns400() {

        Lead leadRecord =
            createAppointmentLead(
                'Invalid Response Client',
                STATUS_PENDING
            );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                'Cancelled',
                null,
                null
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid response should return HTTP 400.'
        );

        System.assertEquals(
            false,
            result.success,
            'Invalid response should fail.'
        );

        System.assertEquals(
            'Invalid appointment response. '
                + 'Allowed values are Approved and '
                + 'Reschedule Requested.',
            result.message,
            'Unexpected invalid response message.'
        );
    }

    /**
     * Verifies required reschedule date validation.
     */
    @IsTest
    static void missingRescheduleDateReturns400() {

        Lead leadRecord =
            createAppointmentLead(
                'Missing Date Client',
                STATUS_PENDING
            );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULE_REQUESTED,
                null,
                RESCHEDULE_TIME_SLOT
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing date should return HTTP 400.'
        );

        System.assertEquals(
            'Preferred reschedule date is required.',
            result.message,
            'Unexpected required-date message.'
        );
    }

    /**
     * Verifies invalid date format.
     */
    @IsTest
    static void invalidRescheduleDateReturns400() {

        Lead leadRecord =
            createAppointmentLead(
                'Invalid Date Client',
                STATUS_PENDING
            );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULE_REQUESTED,
                '10/15/2026',
                RESCHEDULE_TIME_SLOT
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid date should return HTTP 400.'
        );

        System.assertEquals(
            'Preferred date must use YYYY-MM-DD format.',
            result.message,
            'Unexpected invalid date message.'
        );
    }

    /**
     * Verifies past reschedule date validation.
     */
    @IsTest
    static void pastRescheduleDateReturns400() {

        Lead leadRecord =
            createAppointmentLead(
                'Past Date Client',
                STATUS_PENDING
            );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULE_REQUESTED,
                String.valueOf(
                    Date.today().addDays(-1)
                ),
                RESCHEDULE_TIME_SLOT
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Past date should return HTTP 400.'
        );

        System.assertEquals(
            'Preferred date cannot be in the past.',
            result.message,
            'Unexpected past date message.'
        );
    }

    /**
     * Verifies required reschedule time slot.
     */
    @IsTest
    static void missingRescheduleTimeReturns400() {

        Lead leadRecord =
            createAppointmentLead(
                'Missing Time Client',
                STATUS_PENDING
            );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULE_REQUESTED,
                String.valueOf(
                    Date.today().addDays(5)
                ),
                null
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing time should return HTTP 400.'
        );

        System.assertEquals(
            'Preferred time slot is required.',
            result.message,
            'Unexpected missing time message.'
        );
    }

    /**
     * Verifies invalid reschedule time slot.
     */
    @IsTest
    static void invalidRescheduleTimeReturns400() {

        Lead leadRecord =
            createAppointmentLead(
                'Invalid Time Client',
                STATUS_PENDING
            );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULE_REQUESTED,
                String.valueOf(
                    Date.today().addDays(5)
                ),
                '8PM-9PM'
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid time should return HTTP 400.'
        );

        System.assertEquals(
            'Invalid preferred time slot.',
            result.message,
            'Unexpected invalid time message.'
        );
    }

    /**
     * Verifies that today's date is accepted.
     */
    @IsTest
    static void currentDateRescheduleReturnsSuccess() {

        Lead leadRecord =
            createAppointmentLead(
                'Current Date Client',
                STATUS_PENDING
            );

        prepareJsonRequest(
            createPayload(
                leadRecord.Id,
                RESPONSE_RESCHEDULE_REQUESTED,
                String.valueOf(
                    Date.today()
                ),
                '5PM-6PM'
            )
        );

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            executeRequest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Current date should be accepted.'
        );

        System.assertEquals(
            true,
            result.success,
            'Current-date reschedule should succeed.'
        );
    }

    // =========================================================================
    // Test Data Helpers
    // =========================================================================

    /**
     * Creates Lead test data satisfying existing Lead validation rules.
     */
    private static Lead createLead(
        String lastName
    ) {

        User supervisorUser =
            getSupervisorUser();

        String uniqueValue =
            String.valueOf(
                DateTime.now().getTime()
            );

        Lead leadRecord = new Lead(
            FirstName = 'Portal',
            LastName = lastName,
            Company = 'Arelia Test',
            Email =
                'sitevisit.'
                + uniqueValue
                + '@example.com',
            Phone = TEST_PHONE,

            /*
             * Validation:
             * Project Request Submitted must be checked
             * before Approval Status becomes Approved.
             */
            Project_Request_Submitted__c = true,

            /*
             * Validation:
             * Approval Status must be Approved
             * before Supervisor can be assigned.
             */
            Approval_Status__c = STATUS_APPROVED
        );

        Database.DMLOptions options =
            new Database.DMLOptions();

        options.DuplicateRuleHeader.allowSave =
            true;

        Database.SaveResult saveResult =
            Database.insert(
                leadRecord,
                options
            );

        System.assertEquals(
            true,
            saveResult.isSuccess(),
            'Lead should be created successfully.'
        );

        /*
         * Assign Supervisor only after the Lead has
         * Approved Approval Status.
         *
         * Do not populate Supervisor Email or Phone
         * formula fields directly.
         */
        leadRecord.Supervisor_User__c =
            supervisorUser.Id;

        update leadRecord;

        return leadRecord;
    }

    /**
     * Creates a Lead containing an appointment.
     */
    private static Lead createAppointmentLead(
        String lastName,
        String appointmentStatus
    ) {

        Lead leadRecord =
            createLead(
                lastName
            );

        leadRecord.Appointment_Sent_date__c =
            Date.today();

        leadRecord.Appointment_Date__c =
            Date.today().addDays(5);

        leadRecord.Appointment_Time_Slots__c =
            DEFAULT_TIME_SLOT;

        leadRecord.Appointment_Status__c =
            appointmentStatus;

        update leadRecord;

        return leadRecord;
    }

    /**
     * Returns the Supervisor created in @TestSetup.
     */
    private static User getSupervisorUser() {

        return [
            SELECT
                Id,
                Email
            FROM User
            WHERE Alias = :SUPERVISOR_ALIAS
            LIMIT 1
        ];
    }

    /**
     * Returns Lead appointment values for assertions.
     */
    private static Lead getLead(
        Id leadId
    ) {

        return [
            SELECT
                Id,
                Supervisor_User__c,
                Appointment_Sent_date__c,
                Appointment_Date__c,
                Appointment_Time_Slots__c,
                Appointment_Completed__c,
                Appointment_Status__c,
                Appointment_Rejection_Reason__c,
                Appointment_Rescheduled_Time__c,
                Time_Slots__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
    }

    // =========================================================================
    // REST Helpers
    // =========================================================================

    /**
     * Executes the prepared REST request.
     */
    private static
        ProspectSiteVisitResponseRestController.ResponseWrapper
        executeRequest() {

        Test.startTest();

        ProspectSiteVisitResponseRestController.ResponseWrapper result =
            ProspectSiteVisitResponseRestController.submitResponse();

        Test.stopTest();

        return result;
    }

    /**
     * Creates request payload.
     */
    private static Map<String, Object> createPayload(
        Id leadId,
        String responseValue,
        String requestedDate,
        String requestedTimeSlot
    ) {

        Map<String, Object> payload =
            new Map<String, Object>();

        if (leadId != null) {
            payload.put(
                'leadId',
                leadId
            );
        }

        if (responseValue != null) {
            payload.put(
                'response',
                responseValue
            );
        }

        if (requestedDate != null) {
            payload.put(
                'requestedDate',
                requestedDate
            );
        }

        if (requestedTimeSlot != null) {
            payload.put(
                'requestedTimeSlot',
                requestedTimeSlot
            );
        }

        return payload;
    }

    /**
     * Creates REST request from a JSON payload.
     */
    private static void prepareJsonRequest(
        Map<String, Object> payload
    ) {

        prepareRawRequest(
            JSON.serialize(
                payload
            )
        );
    }

    /**
     * Creates REST request using a raw request body.
     */
    private static void prepareRawRequest(
        String requestBody
    ) {

        RestRequest requestValue =
            new RestRequest();

        requestValue.requestUri =
            ENDPOINT;

        requestValue.httpMethod =
            HTTP_POST;

        requestValue.requestBody =
            Blob.valueOf(
                requestBody
            );

        RestContext.request =
            requestValue;

        RestContext.response =
            new RestResponse();
    }

    /**
     * Creates REST request without request body.
     */
    private static void prepareRequestWithoutBody() {

        RestRequest requestValue =
            new RestRequest();

        requestValue.requestUri =
            ENDPOINT;

        requestValue.httpMethod =
            HTTP_POST;

        RestContext.request =
            requestValue;

        RestContext.response =
            new RestResponse();
    }
}