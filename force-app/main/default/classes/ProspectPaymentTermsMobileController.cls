@RestResource(urlMapping='/registration/lead/payment-terms/*')
global without sharing class ProspectPaymentTermsMobileController {

    private static final String STATUS_SENT_TO_CLIENT =
        'Sent for Client Approval';

    private static final String STATUS_CLIENT_APPROVED =
        'Client Approved';

    private static final String STATUS_CLIENT_REQUESTED_CHANGES =
        'Client Requested Changes';


    @HttpGet
    global static void getPaymentTerms() {

        try {
            RestRequest request =
                RestContext.request;

            String leadId =
                request.params.get('leadId');

            if (String.isBlank(leadId)) {
                writeError(
                    400,
                    'leadId is required.'
                );
                return;
            }

            /*
             * -------------------------------------------------
             * GET CONVERTED LEAD
             * -------------------------------------------------
             */
            List<Lead> leads =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'IsConverted, ' +
                        'ConvertedOpportunityId ' +
                    'FROM Lead ' +
                    'WHERE Id = :leadId ' +
                    'LIMIT 1',
                    AccessLevel.SYSTEM_MODE
                );

            if (leads.isEmpty()) {
                writeError(
                    404,
                    'Prospect Lead not found.'
                );
                return;
            }

            Lead prospectLead =
                leads[0];

            if (
                !prospectLead.IsConverted ||
                prospectLead.ConvertedOpportunityId == null
            ) {
                writeError(
                    403,
                    'This prospect is not connected to an Opportunity.'
                );
                return;
            }

            Id opportunityId =
                prospectLead.ConvertedOpportunityId;


            /*
             * -------------------------------------------------
             * GET OPPORTUNITY PAYMENT APPROVAL INFORMATION
             * -------------------------------------------------
             *
             * These API names are based on your existing
             * PaymentTermApproval logic where
             * Opportunity.Payment_Terms_Status__c is used.
             *
             * If your remarks field API names differ,
             * change only those two field names.
             */
            List<Opportunity> opportunities =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'Name, ' +
                        'Payment_Terms_Status__c, ' +
                        'Payment_Term_Client_Remarks__c, ' +
                        'Payment_Term_Manager_Remarks__c ' +
                    'FROM Opportunity ' +
                    'WHERE Id = :opportunityId ' +
                    'LIMIT 1',
                    AccessLevel.SYSTEM_MODE
                );

            if (opportunities.isEmpty()) {
                writeError(
                    404,
                    'Opportunity not found.'
                );
                return;
            }

            Opportunity opportunity =
                opportunities[0];


            /*
             * -------------------------------------------------
             * GET PAYMENT TERM LINES
             * -------------------------------------------------
             *
             * Existing payment-term implementation uses
             * Payment_Term__c.
             */
            if (opportunity.Payment_Terms_Status__c != STATUS_SENT_TO_CLIENT &&
                opportunity.Payment_Terms_Status__c != STATUS_CLIENT_APPROVED &&
                opportunity.Payment_Terms_Status__c != STATUS_CLIENT_REQUESTED_CHANGES) {
                writeJson(200, new Map<String,Object>{'success'=>true, 'paymentTermsAvailable'=>false});
                return;
            }
            List<Payment_Term__c> paymentTerms =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'Name, ' +
                        'Term_Label__c, ' +
                        'Percentage__c, ' +
                        'Due_Date__c, ' +
                        'Payment_Received__c ' +
                    'FROM Payment_Term__c ' +
                    'WHERE Opportunity__c = :opportunityId ' +
                    'ORDER BY Due_Date__c ASC',
                    AccessLevel.SYSTEM_MODE
                );


            List<Object> terms =
                new List<Object>();

            for (
                Payment_Term__c term :
                paymentTerms
            ) {

                Map<String, Object> termData =
                    new Map<String, Object>();

                termData.put(
                    'termId',
                    term.Id
                );

                termData.put(
                    'name',
                    term.Name
                );

                termData.put(
                    'label',
                    String.isBlank(
                        term.Term_Label__c
                    )
                        ? term.Name
                        : term.Term_Label__c
                );

                termData.put(
                    'percentage',
                    term.Percentage__c
                );

                termData.put(
                    'dueDate',
                    term.Due_Date__c
                );

                termData.put(
                    'paymentReceived',
                    term.Payment_Received__c
                );

                terms.add(
                    termData
                );
            }


            String status =
                opportunity.Payment_Terms_Status__c;

            Boolean canRespond =
                status == STATUS_SENT_TO_CLIENT;


            Map<String, Object> paymentData =
                new Map<String, Object>();

            paymentData.put(
                'opportunityId',
                opportunity.Id
            );

            paymentData.put(
                'opportunityName',
                opportunity.Name
            );

            paymentData.put(
                'status',
                status
            );

            paymentData.put(
                'clientRemarks',
                opportunity
                    .Payment_Term_Client_Remarks__c
            );

            paymentData.put(
                'managerRemarks',
                opportunity
                    .Payment_Term_Manager_Remarks__c
            );

            paymentData.put(
                'canRespond',
                canRespond
            );

            paymentData.put(
                'terms',
                terms
            );


            Map<String, Object> response =
                new Map<String, Object>();

            response.put(
                'success',
                true
            );

            response.put(
                'paymentTermsAvailable',
                !terms.isEmpty()
            );

            response.put(
                'paymentTerms',
                paymentData
            );

            writeJson(
                200,
                response
            );

        } catch (Exception e) {

            writeError(
                500,
                'Unable to load Payment Terms: ' +
                e.getMessage()
            );
        }
    }


    @HttpPost
    global static void submitClientResponse() {

        try {
            RestRequest request =
                RestContext.request;

            if (request.requestBody == null) {
                writeError(
                    400,
                    'Request body is required.'
                );
                return;
            }

            Map<String, Object> input =
                (Map<String, Object>)
                JSON.deserializeUntyped(
                    request.requestBody.toString()
                );

            String leadId =
                getInputString(
                    input,
                    'leadId'
                );

            String opportunityId =
                getInputString(
                    input,
                    'opportunityId'
                );

            String action =
                getInputString(
                    input,
                    'action'
                );

            String comments =
                getInputString(
                    input,
                    'comments'
                );

            if (
                String.isBlank(leadId) ||
                String.isBlank(opportunityId) ||
                String.isBlank(action)
            ) {
                writeError(
                    400,
                    'leadId, opportunityId and action are required.'
                );
                return;
            }


            List<Lead> leads =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'IsConverted, ' +
                        'ConvertedOpportunityId ' +
                    'FROM Lead ' +
                    'WHERE Id = :leadId ' +
                    'LIMIT 1',
                    AccessLevel.SYSTEM_MODE
                );

            if (leads.isEmpty()) {
                writeError(
                    404,
                    'Prospect Lead not found.'
                );
                return;
            }

            Lead prospectLead =
                leads[0];

            if (
                !prospectLead.IsConverted ||
                prospectLead.ConvertedOpportunityId == null
            ) {
                writeError(
                    403,
                    'This prospect is not connected to an Opportunity.'
                );
                return;
            }

            if (
                String.valueOf(
                    prospectLead.ConvertedOpportunityId
                ) != opportunityId
            ) {
                writeError(
                    403,
                    'You are not authorized to access these Payment Terms.'
                );
                return;
            }


            Id normalizedOpportunityId;

            try {
                normalizedOpportunityId =
                    (Id) opportunityId;
            } catch (Exception e) {
                writeError(
                    400,
                    'Invalid Opportunity ID.'
                );
                return;
            }


            List<Opportunity> opportunities =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'Payment_Terms_Status__c, ' +
                        'Payment_Term_Client_Remarks__c ' +
                    'FROM Opportunity ' +
                    'WHERE Id = :normalizedOpportunityId ' +
                    'LIMIT 1 FOR UPDATE',
                    AccessLevel.SYSTEM_MODE
                );

            if (opportunities.isEmpty()) {
                writeError(
                    404,
                    'Opportunity not found.'
                );
                return;
            }

            Opportunity opportunity =
                opportunities[0];


            if (
                opportunity.Payment_Terms_Status__c !=
                STATUS_SENT_TO_CLIENT
            ) {
                writeError(
                    409,
                    'These Payment Terms are not currently awaiting client approval.'
                );
                return;
            }


            action =
                action.trim().toUpperCase();

            String newStatus;


            if (action == 'APPROVE') {

                newStatus =
                    STATUS_CLIENT_APPROVED;

            } else if (action ==
                'REQUEST_CHANGES'
            ) {

                if (String.isBlank(comments)) {
                    writeError(
                        400,
                        'Comments are required when requesting changes.'
                    );
                    return;
                }

                newStatus =
                    STATUS_CLIENT_REQUESTED_CHANGES;

            } else {

                writeError(
                    400,
                    'Only APPROVE or REQUEST_CHANGES are allowed.'
                );
                return;
            }


            opportunity.Payment_Terms_Status__c = newStatus;
            opportunity.Payment_Term_Client_Remarks__c = String.isBlank(comments) ? null : comments.trim();
            Database.update(opportunity, AccessLevel.SYSTEM_MODE);


            Map<String, Object> response =
                new Map<String, Object>();

            response.put(
                'success',
                true
            );

            response.put(
                'opportunityId',
                normalizedOpportunityId
            );

            response.put(
                'status',
                newStatus
            );

            response.put(
                'clientRemarks',
                comments
            );

            response.put(
                'message',
                newStatus ==
                    STATUS_CLIENT_APPROVED
                    ? 'Payment Terms approved successfully.'
                    : 'Payment Terms change request submitted successfully.'
            );

            writeJson(
                200,
                response
            );

        } catch (Exception e) {

            writeError(
                500,
                'Unable to submit Payment Terms response: ' +
                e.getMessage()
            );
        }
    }


    private static String getInputString(
        Map<String, Object> input,
        String key
    ) {

        if (
            input == null ||
            !input.containsKey(key) ||
            input.get(key) == null
        ) {
            return null;
        }

        return String.valueOf(
            input.get(key)
        ).trim();
    }


    private static void writeError(
        Integer statusCode,
        String message
    ) {

        writeJson(
            statusCode,
            new Map<String, Object>{
                'success' => false,
                'message' => message
            }
        );
    }


    private static void writeJson(
        Integer statusCode,
        Object body
    ) {

        RestResponse response =
            RestContext.response;
        response.addHeader('Cache-Control', 'no-store');

        response.statusCode =
            statusCode;

        response.addHeader(
            'Content-Type',
            'application/json'
        );

        response.responseBody =
            Blob.valueOf(
                JSON.serialize(body)
            );
    }
}