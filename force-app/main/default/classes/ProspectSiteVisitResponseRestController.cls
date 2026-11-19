@RestResource(
    urlMapping='/registration/lead/site-visit/response'
)
global without sharing class
    ProspectSiteVisitResponseRestController {

    private static final Set<String> ALLOWED_TIME_SLOTS =
        new Set<String>{
            '9AM-10AM',
            '10AM-11AM',
            '11AM-12PM',
            '12PM-1PM',
            '1PM-2PM',
            '2PM-3PM',
            '3PM-4PM',
            '4PM-5PM',
            '5PM-6PM'
        };

    // =========================================================
    // SUBMIT CLIENT APPROVAL OR RESCHEDULE RESPONSE
    // =========================================================
    @HttpPost
    global static ResponseWrapper submitResponse() {
        ResponseWrapper response = new ResponseWrapper();

        try {
            RestContext.response.addHeader(
                'Content-Type',
                'application/json'
            );

            RestRequest requestValue = RestContext.request;

            // -------------------------------------------------
            // Validate request body
            // -------------------------------------------------
            if (
                requestValue == null ||
                requestValue.requestBody == null ||
                String.isBlank(
                    requestValue.requestBody.toString()
                )
            ) {
                RestContext.response.statusCode = 400;

                response.success = false;
                response.message =
                    'Request body is required.';

                return response;
            }

            // -------------------------------------------------
            // Read request payload
            // -------------------------------------------------
            Map<String, Object> payload =
                (Map<String, Object>)
                JSON.deserializeUntyped(
                    requestValue.requestBody.toString()
                );

            String leadId =
                getStringValue(
                    payload,
                    'leadId'
                );

            String responseType =
                getStringValue(
                    payload,
                    'response'
                );

            String requestedDateValue =
                getStringValue(
                    payload,
                    'requestedDate'
                );

            String requestedTimeSlot =
                getStringValue(
                    payload,
                    'requestedTimeSlot'
                );

            // -------------------------------------------------
            // Validate Lead ID
            // -------------------------------------------------
            if (String.isBlank(leadId)) {
                RestContext.response.statusCode = 400;

                response.success = false;
                response.message =
                    'Salesforce Lead ID is required.';

                return response;
            }

            if (!isValidLeadId(leadId)) {
                RestContext.response.statusCode = 400;

                response.success = false;
                response.message =
                    'Invalid Salesforce Lead ID.';

                return response;
            }

            // -------------------------------------------------
            // Validate response type
            // -------------------------------------------------
            if (String.isBlank(responseType)) {
                RestContext.response.statusCode = 400;

                response.success = false;
                response.message =
                    'Appointment response is required.';

                return response;
            }

            /*
             * Run query explicitly in system mode.
             *
             * The endpoint is used by the Experience Cloud
             * Site Guest User, but the client is allowed to
             * update only the controlled appointment fields.
             */
            List<Lead> matchingLeads = [
                SELECT
                    Id,
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
                WITH SYSTEM_MODE
                LIMIT 1
                FOR UPDATE
            ];

            // -------------------------------------------------
            // Lead not found
            // -------------------------------------------------
            if (matchingLeads.isEmpty()) {
                RestContext.response.statusCode = 404;

                response.success = false;
                response.message =
                    'Lead record was not found.';

                return response;
            }

            Lead leadRecord = matchingLeads[0];

            // -------------------------------------------------
            // Check whether appointment exists
            // -------------------------------------------------
            Boolean appointmentAvailable =
                leadRecord.Appointment_Sent_date__c != null ||
                leadRecord.Appointment_Date__c != null ||
                String.isNotBlank(
                    leadRecord.Appointment_Time_Slots__c
                );

            if (!appointmentAvailable) {
                RestContext.response.statusCode = 409;

                response.success = false;
                response.message =
                    'No site visit appointment is available '
                    + 'for response.';

                response.leadId = leadRecord.Id;

                return response;
            }

            /*
             * Client can submit a response only when:
             *
             * Pending
             * Appointment Rescheduled
             */
            Boolean responseAllowed =
                leadRecord.Appointment_Status__c ==
                    'Pending' ||
                leadRecord.Appointment_Status__c ==
                    'Appointment Rescheduled';

            if (!responseAllowed) {
                RestContext.response.statusCode = 409;

                response.success = false;

                response.message =
                    buildAlreadyRespondedMessage(
                        leadRecord.Appointment_Status__c
                    );

                response.leadId = leadRecord.Id;

                response.appointmentStatus =
                    leadRecord.Appointment_Status__c;

                return response;
            }

            // -------------------------------------------------
            // APPROVE APPOINTMENT
            // -------------------------------------------------
            if (
                responseType.equalsIgnoreCase(
                    'Approved'
                )
            ) {
                approveAppointment(
                    leadRecord
                );

                response.message =
                    'Site visit appointment approved '
                    + 'successfully.';

            // -------------------------------------------------
            // REQUEST RESCHEDULE
            // -------------------------------------------------
            } else if (
                responseType.equalsIgnoreCase(
                    'Reschedule Requested'
                ) ||
                responseType.equalsIgnoreCase(
                    'Rescheduled'
                )
            ) {
                Date requestedDate =
                    validateAndParseRequestedDate(
                        requestedDateValue
                    );

                validateRequestedTimeSlot(
                    requestedTimeSlot
                );

                requestReschedule(
                    leadRecord,
                    requestedDate,
                    requestedTimeSlot
                );

                response.message =
                    'Your reschedule request was submitted '
                    + 'successfully.';

            // -------------------------------------------------
            // INVALID RESPONSE
            // -------------------------------------------------
            } else {
                RestContext.response.statusCode = 400;

                response.success = false;
                response.message =
                    'Invalid appointment response. '
                    + 'Allowed values are Approved and '
                    + 'Reschedule Requested.';

                return response;
            }

            /*
             * IMPORTANT FIX:
             *
             * Save the Lead explicitly in system mode.
             * This prevents:
             *
             * DML operation Update not allowed on Lead
             */
            update as system leadRecord;

            // -------------------------------------------------
            // Success response
            // -------------------------------------------------
            RestContext.response.statusCode = 200;

            response.success = true;
            response.leadId = leadRecord.Id;

            response.appointmentStatus =
                leadRecord.Appointment_Status__c;

            response.appointmentConfirmed =
                leadRecord.Appointment_Completed__c;

            response.appointmentDate =
                formatDate(
                    leadRecord.Appointment_Date__c
                );

            response.appointmentTimeSlot =
                leadRecord.Appointment_Time_Slots__c;

            response.requestedDate =
                formatDate(
                    leadRecord
                        .Appointment_Rescheduled_Time__c
                );

            response.requestedTimeSlot =
                leadRecord.Time_Slots__c;

            return response;

        } catch (JSONException exceptionValue) {
            RestContext.response.statusCode = 400;

            response.success = false;
            response.message =
                'Invalid request format.';

            return response;

        } catch (
            SiteVisitValidationException exceptionValue
        ) {
            RestContext.response.statusCode = 400;

            response.success = false;
            response.message =
                exceptionValue.getMessage();

            return response;

        } catch (DmlException exceptionValue) {
            RestContext.response.statusCode = 500;

            response.success = false;

            response.message =
                'Unable to save the appointment response. '
                + getDmlErrorMessage(
                    exceptionValue
                );

            return response;

        } catch (QueryException exceptionValue) {
            RestContext.response.statusCode = 500;

            response.success = false;

            response.message =
                'Unable to retrieve the site visit '
                + 'appointment. '
                + exceptionValue.getMessage();

            return response;

        } catch (Exception exceptionValue) {
            RestContext.response.statusCode = 500;

            response.success = false;

            response.message =
                'Unable to submit the appointment response. '
                + exceptionValue.getMessage();

            return response;
        }
    }

    // =========================================================
    // APPROVE APPOINTMENT
    // =========================================================
    private static void approveAppointment(
        Lead leadRecord
    ) {
        /*
         * Supervisor-selected appointment date and time
         * are already stored in:
         *
         * Appointment_Date__c
         * Appointment_Time_Slots__c
         *
         * Client approval confirms those values.
         */
        leadRecord.Appointment_Status__c =
            'Approved';

        leadRecord.Appointment_Completed__c =
            true;

        leadRecord.Appointment_Rejection_Reason__c =
            null;

        /*
         * Clear temporary reschedule-request fields
         * after final approval.
         */
        leadRecord.Appointment_Rescheduled_Time__c =
            null;

        leadRecord.Time_Slots__c =
            null;
    }

    // =========================================================
    // REQUEST APPOINTMENT RESCHEDULE
    // =========================================================
    private static void requestReschedule(
        Lead leadRecord,
        Date requestedDate,
        String requestedTimeSlot
    ) {
        /*
         * Keep original supervisor appointment values:
         *
         * Appointment_Date__c
         * Appointment_Time_Slots__c
         *
         * Store the client-requested values in:
         *
         * Appointment_Rescheduled_Time__c
         * Time_Slots__c
         */
        leadRecord.Appointment_Status__c =
            'Rescheduled';

        leadRecord.Appointment_Completed__c =
            true;
        // Clear original confirmed appointment
        leadRecord.Appointment_Date__c = null;
        leadRecord.Appointment_Time_Slots__c = null;

        leadRecord.Appointment_Rescheduled_Time__c =
            requestedDate;

        leadRecord.Time_Slots__c =
            requestedTimeSlot;

        leadRecord.Appointment_Rejection_Reason__c =
            null;
    }

    // =========================================================
    // VALIDATE AND PARSE REQUESTED DATE
    // =========================================================
    private static Date validateAndParseRequestedDate(
        String requestedDateValue
    ) {
        if (String.isBlank(requestedDateValue)) {
            throw new SiteVisitValidationException(
                'Preferred reschedule date is required.'
            );
        }

        Date requestedDate;

        try {
            requestedDate =
                Date.valueOf(
                    requestedDateValue
                );
        } catch (Exception exceptionValue) {
            throw new SiteVisitValidationException(
                'Preferred date must use YYYY-MM-DD format.'
            );
        }

        if (requestedDate < Date.today()) {
            throw new SiteVisitValidationException(
                'Preferred date cannot be in the past.'
            );
        }

        return requestedDate;
    }

    // =========================================================
    // VALIDATE REQUESTED TIME SLOT
    // =========================================================
    private static void validateRequestedTimeSlot(
        String requestedTimeSlot
    ) {
        if (String.isBlank(requestedTimeSlot)) {
            throw new SiteVisitValidationException(
                'Preferred time slot is required.'
            );
        }

        if (
            !ALLOWED_TIME_SLOTS.contains(
                requestedTimeSlot
            )
        ) {
            throw new SiteVisitValidationException(
                'Invalid preferred time slot.'
            );
        }
    }

    // =========================================================
    // ALREADY RESPONDED MESSAGE
    // =========================================================
    private static String buildAlreadyRespondedMessage(
        String appointmentStatus
    ) {
        if (appointmentStatus == 'Approved') {
            return
                'You have already approved this appointment.';
        }

        if (appointmentStatus == 'Rescheduled') {
            return
                'You have already requested a new date '
                + 'and time.';
        }

        if (appointmentStatus == 'Rejected') {
            return
                'You have already rejected this appointment.';
        }

        return
            'A response has already been submitted '
            + 'for this appointment.';
    }

    // =========================================================
    // GET STRING VALUE FROM JSON PAYLOAD
    // =========================================================
    private static String getStringValue(
        Map<String, Object> payload,
        String keyName
    ) {
        if (
            payload == null ||
            !payload.containsKey(keyName) ||
            payload.get(keyName) == null
        ) {
            return null;
        }

        String value =
            String.valueOf(
                payload.get(keyName)
            ).trim();

        if (
            String.isBlank(value) ||
            value.toLowerCase() == 'null'
        ) {
            return null;
        }

        return value;
    }

    // =========================================================
    // VALIDATE SALESFORCE LEAD ID
    // =========================================================
    private static Boolean isValidLeadId(
        String leadId
    ) {
        if (String.isBlank(leadId)) {
            return false;
        }

        if (
            leadId.length() != 15 &&
            leadId.length() != 18
        ) {
            return false;
        }

        return leadId.startsWith('00Q');
    }

    // =========================================================
    // FORMAT DATE FOR FLUTTER
    // =========================================================
    private static String formatDate(
        Date dateValue
    ) {
        return dateValue == null
            ? null
            : String.valueOf(dateValue);
    }

    // =========================================================
    // DML ERROR MESSAGE
    // =========================================================
    private static String getDmlErrorMessage(
        DmlException exceptionValue
    ) {
        if (
            exceptionValue == null ||
            exceptionValue.getNumDml() == 0
        ) {
            return
                'An unknown Salesforce update error occurred.';
        }

        String errorMessage =
            exceptionValue.getDmlMessage(0);

        return String.isBlank(errorMessage)
            ? 'An unknown Salesforce update error occurred.'
            : errorMessage;
    }

    // =========================================================
    // RESPONSE WRAPPER
    // =========================================================
    global class ResponseWrapper {
        public Boolean success;
        public String message;

        public Id leadId;

        public String appointmentStatus;
        public Boolean appointmentConfirmed;

        public String appointmentDate;
        public String appointmentTimeSlot;

        public String requestedDate;
        public String requestedTimeSlot;

        public ResponseWrapper() {
            success = false;
            appointmentConfirmed = false;
        }
    }

    // =========================================================
    // CUSTOM VALIDATION EXCEPTION
    // =========================================================
    private class SiteVisitValidationException
        extends Exception {
    }
}