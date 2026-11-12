@RestResource(
    urlMapping='/registration/lead/project-details-reminder'
)
global without sharing class ProspectProjectDetailsReminderApi {

    global class ReminderRequest {
        public String leadId;
        public String fcmToken;
    }

    global class ReminderResponse {
        public Boolean success;
        public Boolean notificationQueued;
        public String message;
        public String leadId;
        public Boolean projectSubmitted;
    }

    @HttpPost
    global static void sendReminder() {

        RestRequest requestValue = RestContext.request;
        RestResponse responseValue = RestContext.response;

        responseValue.addHeader(
            'Content-Type',
            'application/json'
        );

        ReminderResponse output =
            new ReminderResponse();

        try {

            /*
             * Validate request body.
             */
            if (
                requestValue == null ||
                requestValue.requestBody == null
            ) {

                output.success = false;
                output.notificationQueued = false;
                output.message =
                    'Request body is required.';

                responseValue.statusCode = 400;
                responseValue.responseBody =
                    Blob.valueOf(
                        JSON.serialize(output)
                    );

                return;
            }

            /*
             * Deserialize request.
             */
            ReminderRequest input =
                (ReminderRequest) JSON.deserialize(
                    requestValue.requestBody.toString(),
                    ReminderRequest.class
                );

            /*
             * Validate Lead Id.
             */
            if (
                input == null ||
                String.isBlank(input.leadId)
            ) {

                output.success = false;
                output.notificationQueued = false;
                output.message =
                    'Lead Id is required.';

                responseValue.statusCode = 400;
                responseValue.responseBody =
                    Blob.valueOf(
                        JSON.serialize(output)
                    );

                return;
            }

            Id leadId;

            try {

                leadId =
                    Id.valueOf(
                        input.leadId.trim()
                    );

            } catch (Exception exceptionValue) {

                output.success = false;
                output.notificationQueued = false;
                output.message =
                    'Invalid Lead Id.';

                responseValue.statusCode = 400;
                responseValue.responseBody =
                    Blob.valueOf(
                        JSON.serialize(output)
                    );

                return;
            }

            /*
             * Make sure the supplied Id is a Lead Id.
             */
            if (
                leadId.getSObjectType() !=
                Lead.SObjectType
            ) {

                output.success = false;
                output.notificationQueued = false;
                output.message =
                    'The provided record Id is not a Lead Id.';

                responseValue.statusCode = 400;
                responseValue.responseBody =
                    Blob.valueOf(
                        JSON.serialize(output)
                    );

                return;
            }

            /*
             * Read the latest Lead status from Salesforce.
             */
            List<Lead> leads = [
                SELECT
                    Id,
                    IsConverted,
                    Project_Request_Submitted__c
                FROM Lead
                WHERE Id = :leadId
                LIMIT 1
            ];

            if (leads.isEmpty()) {

                output.success = false;
                output.notificationQueued = false;
                output.message =
                    'Lead not found.';

                responseValue.statusCode = 404;
                responseValue.responseBody =
                    Blob.valueOf(
                        JSON.serialize(output)
                    );

                return;
            }

            Lead prospectLead =
                leads[0];

            output.leadId =
                String.valueOf(
                    prospectLead.Id
                );

            output.projectSubmitted =
                prospectLead
                    .Project_Request_Submitted__c ==
                true;

            /*
             * Converted Leads should not use the
             * Prospect Project Details reminder.
             */
            if (
                prospectLead.IsConverted == true
            ) {

                output.success = true;
                output.notificationQueued = false;
                output.message =
                    'Lead has already been converted.';

                responseValue.statusCode = 200;
                responseValue.responseBody =
                    Blob.valueOf(
                        JSON.serialize(output)
                    );

                return;
            }

            /*
             * MAIN BUSINESS CONDITION
             *
             * Project_Request_Submitted__c = true
             * -> Do not send notification.
             *
             * Project_Request_Submitted__c = false
             * -> Queue Project Details notification.
             */
            if (
                prospectLead
                    .Project_Request_Submitted__c ==
                true
            ) {

                output.success = true;
                output.notificationQueued = false;
                output.message =
                    'Project details are already submitted.';

                responseValue.statusCode = 200;
                responseValue.responseBody =
                    Blob.valueOf(
                        JSON.serialize(output)
                    );

                return;
            }

            /*
             * Queue the existing Project Details
             * notification job.
             */
            System.enqueueJob(
                new ProspectProjectDetailsPushJob(
                    prospectLead.Id,
                    input.fcmToken
                )
            );

            output.success = true;
            output.notificationQueued = true;
            output.message =
                'Project Details reminder queued successfully.';

            responseValue.statusCode = 200;
            responseValue.responseBody =
                Blob.valueOf(
                    JSON.serialize(output)
                );

        } catch (Exception exceptionValue) {

            output.success = false;
            output.notificationQueued = false;
            output.message =
                'Error: ' +
                exceptionValue.getMessage();

            responseValue.statusCode = 500;
            responseValue.responseBody =
                Blob.valueOf(
                    JSON.serialize(output)
                );

            System.debug(
                LoggingLevel.ERROR,
                'Project Details reminder error: ' +
                exceptionValue.getMessage()
            );

            System.debug(
                LoggingLevel.ERROR,
                exceptionValue.getStackTraceString()
            );
        }
    }
}