/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ProspectBudgetReviewMobileControllerTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : This test class is for ProspectBudgetReviewMobileController
 */

@IsTest
private class ProspectBudgetReviewMobileControllerTest {

    /**
     * Creates a Lead, converts it to an Opportunity,
     * and prepares Budget Review test data.
     */
    private static Lead client() {

		String uniqueValue =
			String.valueOf(DateTime.now().getTime()) +
			String.valueOf(Math.abs(Crypto.getRandomInteger()));

		Lead lead = new Lead(
			LastName = 'Budget Client ' + uniqueValue,
			Company = 'self ' + uniqueValue,
			Email = 'budget' + uniqueValue + '@example.com',
			Phone = '9' + uniqueValue.right(9),
			Enter_Password__c = 'Example123!',
			Confirm_password__c = 'Example123!',
			Site_Visit_Manager_Approval__c = true,
			Approval_Status__c = 'Approved'
		);

		insert lead;

		Database.LeadConvert conversion =
			new Database.LeadConvert();

		conversion.setLeadId(
			lead.Id
		);

		conversion.setConvertedStatus(
			[
				SELECT MasterLabel
				FROM LeadStatus
				WHERE IsConverted = true
				LIMIT 1
			].MasterLabel
		);

		conversion.setOpportunityName(
			'Budget test project ' + uniqueValue
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

		lead = [
			SELECT
				Id,
				IsConverted,
				ConvertedOpportunityId
			FROM Lead
			WHERE Id = :lead.Id
			LIMIT 1
		];

		Opportunity opportunity =
			new Opportunity(
				Id = lead.ConvertedOpportunityId,
				Budget__c = 100000,
				Supervisor_Estimated_Budget__c = 120000,
				Project_Estimated_Completion_Months__c = '6 Months',
				Budget_Review_Status__c =
					'Sent for Client Approval'
			);

		update opportunity;

		return lead;
	}


    /**
     * Executes POST Budget Review response.
     */
    private static void respond(
        Lead lead,
        Id opportunityId,
        String action,
        String comments
    ) {

        RestContext.request =
            new RestRequest();


        RestContext.request.httpMethod =
            'POST';


        RestContext.request.requestURI =
            '/services/apexrest/registration/lead/budget-review/';


        RestContext.request.requestBody =
            Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'leadId' =>
                            lead.Id,

                        'opportunityId' =>
                            opportunityId,

                        'action' =>
                            action,

                        'comments' =>
                            comments
                    }
                )
            );


        RestContext.response =
            new RestResponse();


        ProspectBudgetReviewMobileController.submitBudgetResponse();
    }


    /**
     * Executes GET Budget Review.
     */
    private static Map<String, Object> readBudget(
        Lead lead
    ) {

        RestContext.request =
            new RestRequest();


        RestContext.request.httpMethod =
            'GET';


        RestContext.request.requestURI =
            '/services/apexrest/registration/lead/budget-review/';


        RestContext.request.addParameter(
            'leadId',
            String.valueOf(
                lead.Id
            )
        );


        RestContext.response =
            new RestResponse();


        ProspectBudgetReviewMobileController.getBudgetReview();


        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'GET Budget Review should return HTTP 200.'
        );


        return (Map<String, Object>)
            JSON.deserializeUntyped(
                RestContext.response
                    .responseBody
                    .toString()
            );
    }


    /**
     * Verify customer budget,
     * supervisor budget,
     * revisit budget,
     * and duration selection logic.
     */
    @IsTest
    static void readsCustomerAndSupervisorBudgets() {

        Lead lead =
            client();


        Map<String, Object> response =
            readBudget(
                lead
            );


        Map<String, Object> budget =
            (Map<String, Object>)
            response.get(
                'budget'
            );


        System.assertEquals(
            Decimal.valueOf('100000'),
            Decimal.valueOf(
                String.valueOf(
                    budget.get(
                        'customerBudget'
                    )
                )
            )
        );


        System.assertEquals(
            Decimal.valueOf('120000'),
            Decimal.valueOf(
                String.valueOf(
                    budget.get(
                        'finalBudget'
                    )
                )
            )
        );


        System.assert(
            budget.containsKey(
                'estimatedDuration'
            )
        );


        /*
         * Revisit budget exists,
         * but revisit duration is missing.
         *
         * Controller must still use
         * original supervisor budget.
         */
        update new Opportunity(
            Id =
                lead.ConvertedOpportunityId,

            Re_Visit_Site_Supervisor_Estimate_Budget__c =
                150000
        );


        budget =
            (Map<String, Object>)
            readBudget(
                lead
            ).get(
                'budget'
            );


        System.assertEquals(
            Decimal.valueOf('120000'),
            Decimal.valueOf(
                String.valueOf(
                    budget.get(
                        'finalBudget'
                    )
                )
            ),
            'Revisit budget must not be used without revisit duration.'
        );


        /*
         * Determine the correct data type dynamically
         * for the Revisit Duration field.
         */
        Schema.DescribeFieldResult durationField =
            Opportunity.SObjectType.getDescribe().fields.getMap().get('ReVisit_Site_Estimated_Completion_Months__c').getDescribe();


        Object duration =
            '4';


        if (
            durationField.getType() ==
            Schema.DisplayType.Picklist
        ) {

            for (
                Schema.PicklistEntry entry :
                durationField.getPicklistValues()
            ) {

                if (
                    entry.isActive()
                ) {

                    duration =
                        entry.getValue();

                    break;
                }
            }

        } else if (
            durationField.getType() ==
                Schema.DisplayType.Double ||
            durationField.getType() ==
                Schema.DisplayType.Integer ||
            durationField.getType() ==
                Schema.DisplayType.Currency
        ) {

            duration =
                Decimal.valueOf(
                    '4'
                );
        }


        Opportunity change =
            new Opportunity(
                Id =
                    lead.ConvertedOpportunityId
            );


        change.put(
            'ReVisit_Site_Estimated_Completion_Months__c',
            duration
        );


        update change;


        /*
         * Now revisit budget + revisit duration exist,
         * so revisit values must be selected.
         */
        budget =
            (Map<String, Object>)
            readBudget(
                lead
            ).get(
                'budget'
            );


        System.assertEquals(
            Decimal.valueOf('150000'),
            Decimal.valueOf(
                String.valueOf(
                    budget.get(
                        'finalBudget'
                    )
                )
            )
        );


        System.assertEquals(
            String.valueOf(
                duration
            ),
            String.valueOf(
                budget.get(
                    'estimatedDuration'
                )
            )
        );


        /*
         * Zero is still considered
         * a populated revisit budget.
         */
        update new Opportunity(
            Id =
                lead.ConvertedOpportunityId,

            Re_Visit_Site_Supervisor_Estimate_Budget__c =
                0
        );


        budget =
            (Map<String, Object>)
            readBudget(
                lead
            ).get(
                'budget'
            );


        System.assertEquals(
            Decimal.valueOf('0'),
            Decimal.valueOf(
                String.valueOf(
                    budget.get(
                        'finalBudget'
                    )
                )
            ),
            'Zero is a populated revisit estimate.'
        );


        /*
         * Duration exists but revisit budget is removed.
         *
         * Controller must fall back to:
         * Supervisor Estimated Budget
         * +
         * Original Project Duration
         */
        update new Opportunity(
            Id =
                lead.ConvertedOpportunityId,

            Re_Visit_Site_Supervisor_Estimate_Budget__c =
                null
        );


        budget =
            (Map<String, Object>)
            readBudget(
                lead
            ).get(
                'budget'
            );


        System.assertEquals(
            Decimal.valueOf('120000'),
            Decimal.valueOf(
                String.valueOf(
                    budget.get(
                        'finalBudget'
                    )
                )
            )
        );

        Opportunity originalOpportunity = [
            SELECT
                Project_Estimated_Completion_Months__c
            FROM Opportunity
            WHERE Id =
                :lead.ConvertedOpportunityId
            LIMIT 1
        ];


        Object originalDuration =
            originalOpportunity
                .Project_Estimated_Completion_Months__c;


        System.assertEquals(
            String.valueOf(
                originalDuration
            ),
            String.valueOf(
                budget.get(
                    'estimatedDuration'
                )
            ),
            'Original duration should be used when revisit budget is null.'
        );
    }


    /**
     * Verify an approved Budget Review
     * cannot later be overwritten.
     */
    @IsTest
    static void approvalCannotBeOverwritten() {

        Lead lead =
            client();


        respond(
            lead,
            lead.ConvertedOpportunityId,
            'APPROVE',
            'Accepted'
        );


        System.assertEquals(
            200,
            RestContext.response.statusCode
        );


        respond(
            lead,
            lead.ConvertedOpportunityId,
            'REQUEST_CHANGES',
            'Overwrite'
        );


        System.assertEquals(
            409,
            RestContext.response.statusCode
        );


        Opportunity saved = [
            SELECT
                Budget_Review_Status__c,
                Budget_Review_Client_Remarks__c
            FROM Opportunity
            WHERE Id =
                :lead.ConvertedOpportunityId
            LIMIT 1
        ];


        System.assertEquals(
            'Client Approved',
            saved.Budget_Review_Status__c
        );


        System.assertEquals(
            'Accepted',
            saved.Budget_Review_Client_Remarks__c
        );
    }


    /**
     * Verify comments are mandatory
     * when requesting changes.
     */
    @IsTest
    static void changesRequireComments() {

        Lead lead =
            client();


        respond(
            lead,
            lead.ConvertedOpportunityId,
            'REQUEST_CHANGES',
            ' '
        );


        System.assertEquals(
            400,
            RestContext.response.statusCode
        );


        respond(
            lead,
            lead.ConvertedOpportunityId,
            'REQUEST_CHANGES',
            ' Reduce estimate '
        );


        System.assertEquals(
            200,
            RestContext.response.statusCode
        );


        Opportunity saved = [
            SELECT
                Budget_Review_Status__c,
                Budget_Review_Client_Remarks__c
            FROM Opportunity
            WHERE Id =
                :lead.ConvertedOpportunityId
            LIMIT 1
        ];


        System.assertEquals(
            'Client Requested Changes',
            saved.Budget_Review_Status__c
        );


        System.assertEquals(
            'Reduce estimate',
            saved.Budget_Review_Client_Remarks__c
        );
    }


    /**
     * Verify:
     * 1. Lead cannot submit another Lead's Opportunity.
     * 2. Budget not sent for approval cannot be submitted.
     */
    @IsTest
    static void unsentAndOtherOpportunityAreBlocked() {

        Lead lead =
            client();


        Lead other =
            client();


        /*
         * Lead tries accessing another
         * Lead's converted Opportunity.
         */
        respond(
            lead,
            other.ConvertedOpportunityId,
            'APPROVE',
            null
        );


        System.assertEquals(
            403,
            RestContext.response.statusCode
        );


        /*
         * Budget Review has not been sent.
         */
        update new Opportunity(
            Id =
                lead.ConvertedOpportunityId,

            Budget_Review_Status__c =
                'Not Sent'
        );


        Map<String, Object> response =
            readBudget(
                lead
            );


        System.assertEquals(
            false,
            response.get(
                'budgetAvailable'
            )
        );


        respond(
            lead,
            lead.ConvertedOpportunityId,
            'APPROVE',
            null
        );


        System.assertEquals(
            409,
            RestContext.response.statusCode
        );
    }
}