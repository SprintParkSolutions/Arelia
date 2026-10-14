/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementNotificationApiTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : This test class is for ClientAgreementNotificationApi
 */

@IsTest
private class ClientAgreementNotificationApiTest {

    private static ClientAgreementNotificationApi.NotificationResponse readNotice(
        String leadId,
        String opportunityId
    ) {
        RestContext.request = new RestRequest();
        RestContext.request.httpMethod = 'GET';

        if (leadId != null) {
            RestContext.request.addParameter('leadId', leadId);
        }

        if (opportunityId != null) {
            RestContext.request.addParameter(
                'opportunityId',
                opportunityId
            );
        }

        RestContext.response = new RestResponse();

        return ClientAgreementNotificationApi.getNotification();
    }


    private static Lead createLead() {

        Lead lead = new Lead(
            LastName = 'Agreement Client',
            Company = 'self',
            Email = 'agreement@example.com',
            Phone = '9876543210',
            Enter_Password__c = 'Example123!',
            Confirm_password__c = 'Example123!',
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = 'Approved'
        );

        insert lead;

        return lead;
    }


    private static Database.LeadConvertResult convertLead(Id leadId) {

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(leadId);

        conversion.setConvertedStatus(
            [
                SELECT MasterLabel
                FROM LeadStatus
                WHERE IsConverted = true
                LIMIT 1
            ].MasterLabel
        );

        conversion.setOpportunityName(
            'Agreement project'
        );

        Database.LeadConvertResult result =
            Database.convertLead(conversion);

        System.assertEquals(
            true,
            result.isSuccess()
        );

        return result;
    }


    /*
     * ---------------------------------------------------------
     * MAIN SUCCESS FLOW
     * ---------------------------------------------------------
     */
    @IsTest
    static void checkboxControlsNoticeAndOwnershipIsChecked() {

        Lead lead = createLead();


        /*
         * Lead not yet converted
         */
        ClientAgreementNotificationApi.NotificationResponse
            beforeConversion =
                readNotice(
                    String.valueOf(lead.Id),
                    null
                );

        System.assertEquals(
            true,
            beforeConversion.success
        );

        System.assertEquals(
            false,
            beforeConversion.showNotification
        );


        /*
         * Convert Lead
         */
        Database.LeadConvertResult result =
            convertLead(lead.Id);


        /*
         * Agreement not sent
         */
        update new Opportunity(
            Id = result.getOpportunityId(),
            Client_Agreement_Sent__c = false
        );


        ClientAgreementNotificationApi.NotificationResponse
            noticeBeforeAgreement =
                readNotice(
                    String.valueOf(lead.Id),
                    null
                );

        System.assertEquals(
            true,
            noticeBeforeAgreement.success
        );

        System.assertEquals(
            false,
            noticeBeforeAgreement.showNotification
        );


        /*
         * Agreement sent
         */
        update new Opportunity(
            Id = result.getOpportunityId(),
            Client_Agreement_Sent__c = true,
            Email__c = 'agreement@example.com'
        );


        ClientAgreementNotificationApi.NotificationResponse notice =
            readNotice(
                String.valueOf(lead.Id),
                null
            );


        System.assertEquals(
            true,
            notice.success
        );

        System.assertEquals(
            true,
            notice.showNotification
        );

        System.assertEquals(
            result.getOpportunityId(),
            notice.opportunityId
        );

        System.assertEquals(
            true,
            notice.notificationMessage.contains(
                'agreement@example.com'
            )
        );

        System.assertEquals(
            'CLIENT_AGREEMENT_SENT',
            notice.notificationType
        );

        System.assertEquals(
            'Client Agreement Available',
            notice.notificationTitle
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode
        );
    }


    /*
     * ---------------------------------------------------------
     * MISSING LEAD ID
     * ---------------------------------------------------------
     */
    @IsTest
    static void missingLeadIdReturns400() {

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                null,
                null
            );

        System.assertEquals(
            false,
            response.success
        );

        System.assertEquals(
            'A valid Lead Id is required.',
            response.message
        );

        System.assertEquals(
            400,
            RestContext.response.statusCode
        );
    }


    /*
     * ---------------------------------------------------------
     * INVALID LEAD ID FORMAT
     * ---------------------------------------------------------
     */
    @IsTest
    static void invalidLeadIdReturns400() {

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                'INVALID_ID',
                null
            );

        System.assertEquals(
            false,
            response.success
        );

        System.assertEquals(
            400,
            RestContext.response.statusCode
        );
    }


    /*
     * ---------------------------------------------------------
     * WRONG SOBJECT TYPE AS LEAD ID
     * ---------------------------------------------------------
     */
    @IsTest
    static void accountIdUsedAsLeadIdReturns400() {

        Account acc = new Account(
            Name = 'Test Account'
        );

        insert acc;


        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(acc.Id),
                null
            );


        System.assertEquals(
            false,
            response.success
        );

        System.assertEquals(
            400,
            RestContext.response.statusCode
        );
    }


    /*
     * ---------------------------------------------------------
     * UNAUTHORIZED OPPORTUNITY
     * ---------------------------------------------------------
     */
    @IsTest
    static void mismatchingOpportunityReturns403() {

        Lead lead = createLead();

        Database.LeadConvertResult result =
            convertLead(lead.Id);


        Opportunity anotherOpp = new Opportunity(
            Name = 'Different Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );

        insert anotherOpp;


        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(lead.Id),
                String.valueOf(anotherOpp.Id)
            );


        System.assertEquals(
            false,
            response.success
        );

        System.assertEquals(
            'You are not authorized to access this Opportunity.',
            response.message
        );

        System.assertEquals(
            403,
            RestContext.response.statusCode
        );
    }


    /*
     * ---------------------------------------------------------
     * WRONG SOBJECT TYPE IN OPPORTUNITY PARAMETER
     * ---------------------------------------------------------
     */
    @IsTest
    static void accountIdAsOpportunityReturns403() {

        Lead lead = createLead();

        Database.LeadConvertResult result =
            convertLead(lead.Id);


        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(lead.Id),
                String.valueOf(result.getAccountId())
            );


        System.assertEquals(
            false,
            response.success
        );

        System.assertEquals(
            403,
            RestContext.response.statusCode
        );
    }


    /*
     * ---------------------------------------------------------
     * EMAIL FALLBACK
     * ---------------------------------------------------------
     */
    @IsTest
    static void blankEmailUsesRegisteredEmailText() {

        Lead lead = createLead();

        Database.LeadConvertResult result =
            convertLead(lead.Id);


        update new Opportunity(
            Id = result.getOpportunityId(),
            Client_Agreement_Sent__c = true,
            Email__c = null
        );


        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(lead.Id),
                null
            );


        System.assertEquals(
            true,
            response.success
        );

        System.assertEquals(
            true,
            response.showNotification
        );

        System.assert(
            response.notificationMessage.contains(
                'your registered email'
            )
        );
    }


    /*
     * ---------------------------------------------------------
     * OPPORTUNITY ID PROVIDED AND MATCHES CONVERTED OPPORTUNITY
     * ---------------------------------------------------------
     */
    @IsTest
    static void matchingOpportunityIdIsAllowed() {

        Lead lead = createLead();

        Database.LeadConvertResult result =
            convertLead(lead.Id);


        update new Opportunity(
            Id = result.getOpportunityId(),
            Client_Agreement_Sent__c = true,
            Email__c = 'agreement@example.com'
        );


        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(lead.Id),
                String.valueOf(result.getOpportunityId())
            );


        System.assertEquals(
            true,
            response.success
        );

        System.assertEquals(
            true,
            response.showNotification
        );

        System.assertEquals(
            result.getOpportunityId(),
            response.opportunityId
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode
        );
    }

	/*
	* ---------------------------------------------------------
	* VALID LEAD ID FORMAT BUT RECORD DOES NOT EXIST
	* ---------------------------------------------------------
	*/
	@IsTest
	static void leadNotFoundReturns404() {

		/*
		* Create a real Lead first so Salesforce generates
		* a valid Lead Id.
		*/
		Lead lead = createLead();

		Id deletedLeadId = lead.Id;


		/*
		* Delete the Lead so the API query:
		*
		* SELECT IsConverted, ConvertedOpportunityId
		* FROM Lead
		* WHERE Id = :leadId
		*
		* returns no rows.
		*/
		delete lead;


		ClientAgreementNotificationApi.NotificationResponse response =
			readNotice(
				String.valueOf(deletedLeadId),
				null
			);


		System.assertEquals(
			false,
			response.success
		);

		System.assertEquals(
			'Prospect Lead not found.',
			response.message
		);

		System.assertEquals(
			404,
			RestContext.response.statusCode
		);
	}

	/*
	* ---------------------------------------------------------
	* CONVERTED OPPORTUNITY NO LONGER AVAILABLE
	* ---------------------------------------------------------
	*/
	@IsTest
	static void convertedOpportunityNotFoundReturns404() {

		Lead lead = createLead();

		Database.LeadConvertResult result =
			convertLead(lead.Id);

		Id opportunityId =
			result.getOpportunityId();


		/*
		* Delete converted Opportunity so the Lead still has
		* ConvertedOpportunityId, but the normal Opportunity
		* query will not return the deleted record.
		*/
		delete new Opportunity(
			Id = opportunityId
		);


		ClientAgreementNotificationApi.NotificationResponse response =
			readNotice(
				String.valueOf(lead.Id),
				null
			);


		System.assertEquals(
			false,
			response.success
		);

		System.assertEquals(
			'Opportunity not found.',
			response.message
		);

		System.assertEquals(
			404,
			RestContext.response.statusCode
		);
	}
}