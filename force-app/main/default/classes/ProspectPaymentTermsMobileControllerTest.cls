/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ProspectPaymentTermsMobileControllerTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : This test class is for ProspectPaymentTermsMobileControllerTest
 */

@IsTest
private class ProspectPaymentTermsMobileControllerTest {

    private static final String PAYMENT_STATUS_SENT_TO_CLIENT =
        'Sent for Client Approval';

    private static final String PAYMENT_STATUS_CLIENT_APPROVED =
        'Client Approved';

    private static final String PAYMENT_STATUS_CLIENT_CHANGES =
        'Client Requested Changes';

    private static final String ACTION_APPROVE =
        'APPROVE';

    private static final String ACTION_REQUEST_CHANGES =
        'REQUEST_CHANGES';

    /**
     * Creates and converts a Lead that satisfies
     * the Lead conversion validation rules.
     */
    private static Lead createClient() {

        Lead lead = new Lead(
            LastName = 'Payment Client',
            Company = 'self',
            Email = generateUniqueEmail(),
            Phone = '9876543210',
            Enter_Password__c = 'Example123!',
            Confirm_password__c = 'Example123!',
            Site_Visit_Manager_Approval__c = true
        );

        /*
         * Lead conversion requires:
         *
         * 1. Site Visit Manager Approval = true
         * 2. Approval Status = Approved
         *
         * The exact Approval Status field API name was not supplied,
         * so locate the Site Visit approval-status field dynamically.
         */
        setSiteVisitApprovalStatus(lead);

        insert lead;

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(
            lead.Id
        );

        conversion.setConvertedStatus(
            getConvertedLeadStatus()
        );

        conversion.setOpportunityName(
            'Payment test project'
        );

        Database.LeadConvertResult conversionResult =
            Database.convertLead(
                conversion
            );

        System.assertEquals(
            true,
            conversionResult.isSuccess(),
            'Lead conversion should succeed when manager approval ' +
            'and approval status requirements are satisfied.'
        );

        Lead convertedLead = [
            SELECT
                Id,
                IsConverted,
                ConvertedOpportunityId
            FROM Lead
            WHERE Id = :lead.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            convertedLead.IsConverted,
            'Lead should be converted.'
        );

        System.assertNotEquals(
            null,
            convertedLead.ConvertedOpportunityId,
            'Converted Lead should have an Opportunity.'
        );

        Opportunity opportunity =
            new Opportunity(
                Id = convertedLead.ConvertedOpportunityId,
                Payment_Terms_Status__c =
                    PAYMENT_STATUS_SENT_TO_CLIENT
            );

        update opportunity;

        Payment_Term__c paymentTerm =
            new Payment_Term__c(
                Opportunity__c =
                    convertedLead.ConvertedOpportunityId,
                Percentage__c = 25,
                Due_Date__c =
                    Date.today().addDays(10)
            );

        if (
            !Payment_Term__c.Name
                .getDescribe()
                .isAutoNumber()
        ) {
            paymentTerm.Name =
                'Booking';
        }

        insert paymentTerm;

        return convertedLead;
    }

    /**
     * Sets the Site Visit Approval Status to Approved.
     *
     * This helper avoids hard-coding the Approval Status
     * field API name because only the Manager Approval
     * checkbox API name was provided.
     */
    private static void setSiteVisitApprovalStatus(
        Lead lead
    ) {

        Map<String, Schema.SObjectField> leadFields =
            Schema.SObjectType.Lead.fields.getMap();

        /*
         * Check the most likely API names first.
         */
        List<String> candidateFieldNames =
            new List<String>{
                'Site_Visit_Approval_Status__c',
                'Site_Visit_Manager_Approval_Status__c',
                'Site_Visit_Report_Approval_Status__c',
                'Approval_Status__c'
            };

        for (
            String fieldApiName :
            candidateFieldNames
        ) {

            if (
                leadFields.containsKey(
                    fieldApiName
                ) &&
                setApprovedValue(
                    lead,
                    leadFields.get(fieldApiName)
                )
            ) {
                return;
            }
        }

        /*
         * Fallback:
         *
         * Search custom fields whose field label/API name
         * indicates that they are the Site Visit
         * Approval Status field.
         */
        for (
            String fieldApiName :
            leadFields.keySet()
        ) {

            Schema.DescribeFieldResult fieldDescribe =
                leadFields
                    .get(fieldApiName)
                    .getDescribe();

            String fieldLabel =
                fieldDescribe.getLabel();

            String normalizedApiName =
                fieldApiName.toLowerCase();

            String normalizedLabel =
                String.isBlank(fieldLabel)
                    ? ''
                    : fieldLabel.toLowerCase();

            Boolean isApprovalStatusField =
                normalizedLabel.contains(
                    'approval status'
                );

            Boolean isSiteVisitField =
                normalizedLabel.contains(
                    'site visit'
                ) ||
                normalizedApiName.contains(
                    'site_visit'
                );

            if (
                isApprovalStatusField &&
                isSiteVisitField &&
                setApprovedValue(
                    lead,
                    leadFields.get(fieldApiName)
                )
            ) {
                return;
            }
        }
    }

    /**
     * Sets Approved only when the field supports
     * that value.
     */
    private static Boolean setApprovedValue(
        Lead lead,
        Schema.SObjectField fieldReference
    ) {

        Schema.DescribeFieldResult fieldDescribe =
            fieldReference.getDescribe();

        if (
            !fieldDescribe.isCreateable()
        ) {
            return false;
        }

        if (
            fieldDescribe.getType() ==
            Schema.DisplayType.Picklist
        ) {

            for (
                Schema.PicklistEntry entry :
                fieldDescribe.getPicklistValues()
            ) {

                if (
                    entry.isActive() &&
                    entry.getValue() == 'Approved'
                ) {

                    lead.put(
                        fieldDescribe.getName(),
                        'Approved'
                    );

                    return true;
                }
            }

            return false;
        }

        if (
            fieldDescribe.getType() ==
                Schema.DisplayType.String
        ) {

            lead.put(
                fieldDescribe.getName(),
                'Approved'
            );

            return true;
        }

        return false;
    }

    /**
     * Gets an active converted Lead Status.
     */
    private static String getConvertedLeadStatus() {

        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        return convertedStatus.MasterLabel;
    }

    /**
     * Generates a unique email for each Lead.
     *
     * This also helps prevent duplicate-rule failures
     * when multiple test Leads are created.
     */
    private static String generateUniqueEmail() {

        return 'payment.' +
            String.valueOf(
                Crypto.getRandomLong()
            ).replace('-', '') +
            '@example.com';
    }

    /**
     * Calls the POST REST endpoint.
     */
    private static void respond(
        Lead lead,
        Id opportunityId,
        String action,
        String comments
    ) {

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'POST';

        request.requestURI =
            '/services/apexrest/registration/lead/payment-terms/';

        request.requestBody =
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

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();

        ProspectPaymentTermsMobileController.submitClientResponse();
    }

    /**
     * Calls the GET REST endpoint.
     */
    private static Map<String, Object> readTerms(
        Lead lead
    ) {

        RestRequest request =
            new RestRequest();

        request.httpMethod =
            'GET';

        request.requestURI =
            '/services/apexrest/registration/lead/payment-terms/';

        request.addParameter(
            'leadId',
            String.valueOf(
                lead.Id
            )
        );

        RestContext.request =
            request;

        RestContext.response =
            new RestResponse();

        ProspectPaymentTermsMobileController.getPaymentTerms();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'GET Payment Terms should return HTTP 200.'
        );

        return (Map<String, Object>)
            JSON.deserializeUntyped(
                RestContext.response
                    .responseBody
                    .toString()
            );
    }

    @IsTest
    static void returnsScheduleAndHidesInternalReviews() {

        Lead lead =
            createClient();

        Map<String, Object> response =
            readTerms(
                lead
            );

        System.assertEquals(
            true,
            response.get(
                'paymentTermsAvailable'
            ),
            'Payment Terms should be available.'
        );

        Map<String, Object> payment =
            (Map<String, Object>)
            response.get(
                'paymentTerms'
            );

        List<Object> terms =
            (List<Object>)
            payment.get(
                'terms'
            );

        System.assertEquals(
            1,
            terms.size(),
            'One Payment Term should be returned.'
        );

        Map<String, Object> term =
            (Map<String, Object>)
            terms[0];

        System.assertEquals(
            25,
            term.get(
                'percentage'
            ),
            'Percentage should match the Payment Term.'
        );

        System.assertEquals(
            String.valueOf(
                Date.today().addDays(10)
            ),
            term.get(
                'dueDate'
            ),
            'Due date should match.'
        );

        System.assertNotEquals(
            null,
            term.get(
                'label'
            ),
            'Payment Term label should be populated.'
        );

        Opportunity opportunity =
            new Opportunity(
                Id =
                    lead.ConvertedOpportunityId,
                Payment_Terms_Status__c =
                    'Sent for Manager Approval'
            );

        update opportunity;

        Map<String, Object> hiddenResponse =
            readTerms(
                lead
            );

        System.assertEquals(
            false,
            hiddenResponse.get(
                'paymentTermsAvailable'
            ),
            'Internal manager review should not be shown to client.'
        );
    }

    @IsTest
    static void approvalCannotBeOverwrittenAndClearsOldRemarks() {

        Lead lead =
            createClient();

        Opportunity opportunity =
            new Opportunity(
                Id =
                    lead.ConvertedOpportunityId,
                Payment_Term_Client_Remarks__c =
                    'Earlier request'
            );

        update opportunity;

        Test.startTest();

        respond(
            lead,
            lead.ConvertedOpportunityId,
            ACTION_APPROVE,
            null
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Initial approval should succeed.'
        );

        respond(
            lead,
            lead.ConvertedOpportunityId,
            ACTION_REQUEST_CHANGES,
            'Overwrite'
        );

        Test.stopTest();

        System.assertEquals(
            409,
            RestContext.response.statusCode,
            'Approved Payment Terms should not be overwritten.'
        );

        Opportunity savedOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :lead.ConvertedOpportunityId
            LIMIT 1
        ];

        System.assertEquals(
            PAYMENT_STATUS_CLIENT_APPROVED,
            savedOpportunity.Payment_Terms_Status__c,
            'Payment Terms should remain Client Approved.'
        );

        System.assertEquals(
            null,
            savedOpportunity.Payment_Term_Client_Remarks__c,
            'Old client remarks should be cleared after approval.'
        );
    }

    @IsTest
    static void changesRequireCommentsAndCanBeResent() {

        Lead lead =
            createClient();

        respond(
            lead,
            lead.ConvertedOpportunityId,
            ACTION_REQUEST_CHANGES,
            ' '
        );

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Change requests without comments should be rejected.'
        );

        respond(
            lead,
            lead.ConvertedOpportunityId,
            ACTION_REQUEST_CHANGES,
            ' Change date '
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Valid change request should succeed.'
        );

        Opportunity savedOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :lead.ConvertedOpportunityId
            LIMIT 1
        ];

        System.assertEquals(
            PAYMENT_STATUS_CLIENT_CHANGES,
            savedOpportunity.Payment_Terms_Status__c,
            'Status should indicate client requested changes.'
        );

        System.assertEquals(
            'Change date',
            savedOpportunity.Payment_Term_Client_Remarks__c,
            'Client remarks should be trimmed and saved.'
        );

        savedOpportunity.Payment_Terms_Status__c =
            PAYMENT_STATUS_SENT_TO_CLIENT;

        update savedOpportunity;

        Test.startTest();

        respond(
            lead,
            lead.ConvertedOpportunityId,
            ACTION_APPROVE,
            null
        );

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Resent Payment Terms should be approvable.'
        );
    }

    @IsTest
    static void changeRequestDoesNotDependOnPaymentLineCount() {

        Lead lead =
            createClient();

        List<Payment_Term__c> paymentTerms = [
            SELECT Id
            FROM Payment_Term__c
            WHERE Opportunity__c =
                :lead.ConvertedOpportunityId
        ];

        delete paymentTerms;

        respond(
            lead,
            lead.ConvertedOpportunityId,
            ACTION_REQUEST_CHANGES,
            ' First: 35, Second: 35, Third: 30 '
        );

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Change request should work even with no Payment Term rows.'
        );

        Opportunity savedOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :lead.ConvertedOpportunityId
            LIMIT 1
        ];

        System.assertEquals(
            PAYMENT_STATUS_CLIENT_CHANGES,
            savedOpportunity.Payment_Terms_Status__c,
            'Status should be Client Requested Changes.'
        );

        System.assertEquals(
            'First: 35, Second: 35, Third: 30',
            savedOpportunity.Payment_Term_Client_Remarks__c,
            'Remarks should be trimmed before being saved.'
        );

        respond(
            lead,
            lead.ConvertedOpportunityId,
            ACTION_REQUEST_CHANGES,
            'Duplicate'
        );

        System.assertEquals(
            409,
            RestContext.response.statusCode,
            'A duplicate response should be rejected.'
        );
    }

    @IsTest
    static void rejectsUnrelatedOpportunity() {

        Lead firstLead =
            createClient();

        Lead secondLead =
            createClient();

        Test.startTest();

        respond(
            firstLead,
            secondLead.ConvertedOpportunityId,
            ACTION_APPROVE,
            null
        );

        Test.stopTest();

        System.assertEquals(
            403,
            RestContext.response.statusCode,
            'A client should not access another Opportunity.'
        );
    }
}