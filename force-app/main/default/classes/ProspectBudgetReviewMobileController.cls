@RestResource(urlMapping='/registration/lead/budget-review/*')
global without sharing class ProspectBudgetReviewMobileController {

    /*
     * =========================================================
     * BUDGET REVIEW STATUS VALUES
     * =========================================================
     */
    private static final String STATUS_SENT =
        'Sent for Client Approval';

    private static final String STATUS_CLIENT_APPROVED =
        'Client Approved';

    private static final String STATUS_CLIENT_REQUESTED_CHANGES =
        'Client Requested Changes';


    // Optional manager remarks retain the supplied label-based lookup.
    private static final List<String> MANAGER_REMARKS_LABELS =
        new List<String>{
            'Budget Review Manager Remarks'
        };


    /*
     * =========================================================
     * GET BUDGET REVIEW
     * =========================================================
     */
    @HttpGet
    global static void getBudgetReview() {

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
             * =================================================
             * FIND OPPORTUNITY FROM CONVERTED LEAD
             * =================================================
             */
            Lead prospectLead =
                getConvertedLead(
                    leadId
                );


            if (prospectLead == null) {
                return;
            }


            /*
             * =================================================
             * RESOLVE FIELD API NAMES
             * =================================================
             */
            String supervisorBudgetField =
                'Supervisor_Estimated_Budget__c';

            String revisitBudgetField =
                'Re_Visit_Site_Supervisor_Estimate_Budget__c';

            String statusField =
                'Budget_Review_Status__c';

            String clientRemarksField =
                'Budget_Review_Client_Remarks__c';

            String managerRemarksField =
                findOpportunityField(
                    MANAGER_REMARKS_LABELS
                );


            /*
             * Required fields.
             */
            if (String.isBlank(supervisorBudgetField)) {

                writeError(
                    500,
                    'Salesforce field "Supervisor Estimated Budget" was not found.'
                );

                return;
            }


            if (String.isBlank(revisitBudgetField)) {

                writeError(
                    500,
                    'Salesforce Re-Visit Supervisor Budget field was not found.'
                );

                return;
            }


            if (String.isBlank(statusField)) {

                writeError(
                    500,
                    'Salesforce field "Budget Review Status" was not found.'
                );

                return;
            }


            if (String.isBlank(clientRemarksField)) {

                writeError(
                    500,
                    'Salesforce field "Budget Review Client Remarks" was not found.'
                );

                return;
            }


            /*
             * Manager remarks can be optional.
             */
            List<String> fields =
                new List<String>{
                    'Id',
                    'Name', 'Budget__c', 'Project_Estimated_Completion_Months__c', 'ReVisit_Site_Estimated_Completion_Months__c',
                    supervisorBudgetField,
                    revisitBudgetField,
                    statusField,
                    clientRemarksField
                };


            if (!String.isBlank(managerRemarksField)) {

                fields.add(
                    managerRemarksField
                );
            }


            Id opportunityId =
                prospectLead.ConvertedOpportunityId;


            String query =
                'SELECT ' +
                String.join(
                    fields,
                    ','
                ) +
                ' FROM Opportunity ' +
                'WHERE Id = :opportunityId ' +
                'LIMIT 1';


            List<SObject> opportunityList =
                Database.query(
                    query,
                    AccessLevel.SYSTEM_MODE
                );


            if (opportunityList.isEmpty()) {

                writeError(
                    404,
                    'Opportunity not found.'
                );

                return;
            }


            SObject opportunity =
                opportunityList[0];


            /*
             * =================================================
             * GET BUDGET VALUES
             * =================================================
             */
            Decimal supervisorBudget =
                getDecimalValue(
                    opportunity,
                    supervisorBudgetField
                );


            Decimal revisitBudget =
                getDecimalValue(
                    opportunity,
                    revisitBudgetField
                );


            /*
             * =================================================
             * FINAL BUDGET LOGIC
             * =================================================
             */
            Decimal finalBudget;

            String finalBudgetSource;


            Object revisitDuration = opportunity.get('ReVisit_Site_Estimated_Completion_Months__c');
            Boolean useRevisit = revisitBudget != null && revisitDuration != null
                && !String.isBlank(String.valueOf(revisitDuration));
            Object finalDuration = useRevisit ? revisitDuration
                : opportunity.get('Project_Estimated_Completion_Months__c');

            if (useRevisit) {

                finalBudget =
                    revisitBudget;

                finalBudgetSource =
                    'Re-Visit Site Supervisor Estimate';

            } else {

                finalBudget =
                    supervisorBudget;

                finalBudgetSource =
                    'Supervisor Estimate';
            }


            String status =
                getStringValue(
                    opportunity,
                    statusField
                );


            String clientRemarks =
                getStringValue(
                    opportunity,
                    clientRemarksField
                );


            String managerRemarks;


            if (!String.isBlank(managerRemarksField)) {

                managerRemarks =
                    getStringValue(
                        opportunity,
                        managerRemarksField
                    );
            }


            /*
             * Client can only respond when sent for approval.
             */
            if (String.isBlank(status) || status == 'Not Sent') {
                writeJson(200, new Map<String, Object>{'success' => true, 'budgetAvailable' => false});
                return;
            }
            Boolean canRespond =
                status == STATUS_SENT;


            /*
             * =================================================
             * RESPONSE
             * =================================================
             */
            Map<String, Object> budget =
                new Map<String, Object>();


            budget.put(
                'opportunityId',
                opportunity.get('Id')
            );

            budget.put(
                'opportunityName',
                opportunity.get('Name')
            );

            budget.put(
                'supervisorEstimatedBudget',
                supervisorBudget
            );

            budget.put(
                'revisitSupervisorEstimatedBudget',
                revisitBudget
            );

            budget.put(
                'finalBudget',
                finalBudget
            );

            budget.put(
                'finalBudgetSource',
                finalBudgetSource
            );

            budget.put('customerBudget', opportunity.get('Budget__c'));
            budget.put('estimatedDuration', finalDuration);
            budget.put(
                'status',
                status
            );

            budget.put(
                'clientRemarks',
                clientRemarks
            );

            budget.put(
                'managerRemarks',
                managerRemarks
            );

            budget.put(
                'canRespond',
                canRespond
            );


            Map<String, Object> response =
                new Map<String, Object>();


            response.put(
                'success',
                true
            );

            response.put(
                'budgetAvailable',
                true
            );

            response.put(
                'budget',
                budget
            );


            writeJson(
                200,
                response
            );

        } catch (Exception e) {

            writeError(
                500,
                'Unable to get Budget Review: ' +
                e.getMessage()
            );
        }
    }


    /*
     * =========================================================
     * SUBMIT CLIENT RESPONSE
     * =========================================================
     */
    @HttpPost
    global static void submitBudgetResponse() {

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


            if (String.isBlank(leadId)) {

                writeError(
                    400,
                    'leadId is required.'
                );

                return;
            }


            if (String.isBlank(opportunityId)) {

                writeError(
                    400,
                    'opportunityId is required.'
                );

                return;
            }


            if (String.isBlank(action)) {

                writeError(
                    400,
                    'action is required.'
                );

                return;
            }


            Lead prospectLead =
                getConvertedLead(
                    leadId
                );


            if (prospectLead == null) {
                return;
            }


            /*
             * Prevent another Opportunity from being submitted.
             */
            if (
                String.valueOf(
                    prospectLead.ConvertedOpportunityId
                ) != opportunityId
            ) {

                writeError(
                    403,
                    'You are not authorized to access this Budget Review.'
                );

                return;
            }


            String statusField =
                'Budget_Review_Status__c';

            String clientRemarksField =
                'Budget_Review_Client_Remarks__c';


            if (
                String.isBlank(statusField) ||
                String.isBlank(clientRemarksField)
            ) {

                writeError(
                    500,
                    'Budget Review Salesforce fields are not configured correctly.'
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


            String opportunityQuery =
                'SELECT Id,' +
                statusField +
                ',' +
                clientRemarksField +
                ' FROM Opportunity ' +
                'WHERE Id = :normalizedOpportunityId ' +
                'LIMIT 1 FOR UPDATE';


            List<SObject> opportunities =
                Database.query(
                    opportunityQuery,
                    AccessLevel.SYSTEM_MODE
                );


            if (opportunities.isEmpty()) {

                writeError(
                    404,
                    'Opportunity not found.'
                );

                return;
            }


            SObject opportunity =
                opportunities[0];


            String currentStatus =
                getStringValue(
                    opportunity,
                    statusField
                );


            /*
             * =================================================
             * ONLY ALLOW RESPONSE WHEN SENT
             * =================================================
             */
            if (
                currentStatus != STATUS_SENT
            ) {

                writeError(409,
                    'This Budget Review is not currently awaiting client approval.'
                );

                return;
            }


            action =
                action.trim().toUpperCase();


            String newStatus;


            /*
             * =================================================
             * APPROVE
             * =================================================
             */
            if (
                action == 'APPROVE'
            ) {

                newStatus =
                    STATUS_CLIENT_APPROVED;
            }


            /*
             * =================================================
             * REQUEST CHANGES
             * =================================================
             */
            else if (
                action == 'REQUEST_CHANGES'
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
            }


            else {

                writeError(
                    400,
                    'Only APPROVE or REQUEST_CHANGES are allowed.'
                );

                return;
            }


            /*
             * =================================================
             * LOCKED SYNCHRONOUS UPDATE
             * =================================================
             */
            opportunity.put(statusField, newStatus);
            if (!String.isBlank(comments)) opportunity.put(clientRemarksField, comments.trim());
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
                opportunity.get(clientRemarksField)
            );


            if (
                newStatus ==
                STATUS_CLIENT_APPROVED
            ) {

                response.put(
                    'message',
                    'Budget approved successfully.'
                );

            } else {

                response.put(
                    'message',
                    'Budget change request submitted successfully.'
                );
            }


            writeJson(
                200,
                response
            );

        } catch (Exception e) {

            writeError(
                500,
                'Unable to submit Budget Review response: ' +
                e.getMessage()
            );
        }
    }


    /*
     * =========================================================
     * GET CONVERTED LEAD
     * =========================================================
     */
    private static Lead getConvertedLead(
        String leadId
    ) {

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

            return null;
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

            return null;
        }


        return prospectLead;
    }


    /*
     * =========================================================
     * FIND OPPORTUNITY FIELD BY LABEL
     * =========================================================
     */
    private static String findOpportunityField(
        List<String> possibleLabels
    ) {

        Map<String, Schema.SObjectField> fieldMap =
            Opportunity.SObjectType
                .getDescribe()
                .fields
                .getMap();


        for (String apiName : fieldMap.keySet()) {

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap
                    .get(apiName)
                    .getDescribe();


            String fieldLabel =
                fieldDescribe.getLabel();


            for (String expectedLabel : possibleLabels) {

                if (
                    fieldLabel != null &&
                    expectedLabel != null &&
                    fieldLabel.trim().equalsIgnoreCase(
                        expectedLabel.trim()
                    )
                ) {

                    return apiName;
                }
            }
        }


        return null;
    }


    /*
     * =========================================================
     * DECIMAL HELPER
     * =========================================================
     */
    private static Decimal getDecimalValue(
        SObject record,
        String fieldName
    ) {

        if (
            record == null ||
            String.isBlank(fieldName)
        ) {

            return null;
        }


        Object value =
            record.get(fieldName);


        if (value == null) {

            return null;
        }


        return Decimal.valueOf(
            String.valueOf(value)
        );
    }


    /*
     * =========================================================
     * STRING HELPER
     * =========================================================
     */
    private static String getStringValue(
        SObject record,
        String fieldName
    ) {

        if (
            record == null ||
            String.isBlank(fieldName)
        ) {

            return null;
        }


        Object value =
            record.get(fieldName);


        if (value == null) {

            return null;
        }


        return String.valueOf(
            value
        );
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


    /*
     * =========================================================
     * ERROR
     * =========================================================
     */
    private static void writeError(
        Integer statusCode,
        String message
    ) {

        Map<String, Object> response =
            new Map<String, Object>();


        response.put(
            'success',
            false
        );

        response.put(
            'budgetAvailable',
            false
        );

        response.put(
            'message',
            message
        );


        writeJson(
            statusCode,
            response
        );
    }


    /*
     * =========================================================
     * JSON
     * =========================================================
     */
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