/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementNotificationApi
 * Author          : Mohit
 * Created Date    : Sep 23, 2026
 * Last Modified By: Mohit
 * Last Modified On: Sep 23, 2026
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Sep 23, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@RestResource(urlMapping='/client-portal/client-agreement-notification')
global without sharing class ClientAgreementNotificationApi {

    global class NotificationResponse {
        public Boolean success = false;
        public String message;

        public Id opportunityId;
        public String opportunityName;

        public String clientEmail;

        public Boolean clientAgreementSent = false;

        public Boolean showNotification = false;
        public String notificationTitle;
        public String notificationMessage;
        public String notificationType;
    }

    @HttpGet
    global static NotificationResponse getNotification() {

        NotificationResponse response = new NotificationResponse();
        RestContext.response.addHeader('Cache-Control', 'no-store');

        RestContext.response.addHeader(
            'Content-Type',
            'application/json'
        );

        try {

            // Get Opportunity Id from request
            String opportunityIdParam =
                RestContext.request.params.get('opportunityId');

            // Resolve the signed-in prospect's converted Opportunity, as in the other portal APIs.
            String leadIdParam = RestContext.request.params.get('leadId');
            Id leadId;
            try {
                leadId = Id.valueOf(leadIdParam);
                if (leadId.getSObjectType() != Lead.SObjectType) throw new IllegalArgumentException();
            } catch (Exception invalidId) {
                response.message = 'A valid Lead Id is required.';
                RestContext.response.statusCode = 400;
                return response;
            }
            List<Lead> leads = [SELECT IsConverted, ConvertedOpportunityId FROM Lead WHERE Id=:leadId LIMIT 1];
            if (leads.isEmpty()) {
                response.message = 'Prospect Lead not found.';
                RestContext.response.statusCode = 404;
                return response;
            }
            if (!leads[0].IsConverted || leads[0].ConvertedOpportunityId == null) {
                response.success = true;
                RestContext.response.statusCode = 200;
                return response;
            }
            if (!String.isBlank(opportunityIdParam) && opportunityIdParam != String.valueOf(leads[0].ConvertedOpportunityId)) {
                response.message = 'You are not authorized to access this Opportunity.';
                RestContext.response.statusCode = 403;
                return response;
            }
            opportunityIdParam = String.valueOf(leads[0].ConvertedOpportunityId);
            if (String.isBlank(opportunityIdParam)) {
                response.success = false;
                response.message = 'Opportunity Id is required.';
                RestContext.response.statusCode = 400;
                return response;
            }

            Id opportunityId;

            // Validate Opportunity Id
            try {

                opportunityId =
                    Id.valueOf(opportunityIdParam.trim());

                if (
                    opportunityId.getSObjectType()
                    != Opportunity.SObjectType
                ) {
                    response.success = false;
                    response.message = 'Invalid Opportunity Id.';
                    RestContext.response.statusCode = 400;
                    return response;
                }

            } catch (Exception e) {

                response.success = false;
                response.message = 'Invalid Opportunity Id.';
                RestContext.response.statusCode = 400;
                return response;
            }


            // Retrieve Opportunity information
            List<Opportunity> opportunities = [
                SELECT
                    Id,
                    Name,
                    Email__c,
                    Client_Agreement_Sent__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];


            // Opportunity not found
            if (opportunities.isEmpty()) {

                response.success = false;
                response.message = 'Opportunity not found.';
                RestContext.response.statusCode = 404;

                return response;
            }


            Opportunity opp = opportunities[0];


            // Set Opportunity information
            response.opportunityId = opp.Id;
            response.opportunityName = opp.Name;

            response.clientEmail = opp.Email__c;

            response.clientAgreementSent =
                opp.Client_Agreement_Sent__c;


            // Client Agreement notification
            if (opp.Client_Agreement_Sent__c == true) {

                response.showNotification = true;

                response.notificationTitle =
                    'Client Agreement Available';


                // Use Email__c if available
                String emailText =
                    String.isNotBlank(opp.Email__c)
                    ? opp.Email__c
                    : 'your registered email';


                response.notificationMessage =
                    'Your Client Agreement has been sent to '
                    + emailText
                    + '. Please review and sign the agreement.';


                response.notificationType =
                    'CLIENT_AGREEMENT_SENT';

            } else {

                response.showNotification = false;
            }


            response.success = true;
            RestContext.response.statusCode = 200;
            response.message =
                'Notification status retrieved successfully.';


        } catch (Exception e) {

            response.success = false;

            response.message =
                'Unable to retrieve notification status: '
                + e.getMessage();

            RestContext.response.statusCode = 500;
        }


        return response;
    }
}