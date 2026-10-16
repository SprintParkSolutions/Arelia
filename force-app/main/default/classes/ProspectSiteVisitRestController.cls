@RestResource(urlMapping='/registration/lead/site-visit')
global without sharing class ProspectSiteVisitRestController {

    private static final List<String> AVAILABLE_TIME_SLOTS =
        new List<String>{
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

    @HttpGet
    global static SiteVisitResponse getSiteVisit() {
        SiteVisitResponse response = new SiteVisitResponse();

        try {
            RestContext.response.addHeader(
                'Content-Type',
                'application/json'
            );

            RestRequest requestValue = RestContext.request;

            String leadId = requestValue == null
                ? null
                : requestValue.params.get('leadId');

            if (String.isBlank(leadId)) {
                RestContext.response.statusCode = 400;

                response.success = false;
                response.message =
                    'Salesforce Lead ID is required.';
                response.appointmentAvailable = false;

                return response;
            }

            leadId = leadId.trim();

            if (!isValidLeadId(leadId)) {
                RestContext.response.statusCode = 400;

                response.success = false;
                response.message =
                    'Invalid Salesforce Lead ID.';
                response.appointmentAvailable = false;

                return response;
            }

            List<Lead> matchingLeads = [
                SELECT
                    Id,
                    FirstName,
                    LastName,
                    Email,
                    Phone,
                    Site_Location__c,
                    Supervisor_User__c,
                    Supervisor_User__r.Name,
                    Supervisor_User_Email__c,
                    Supervisor_User_Phone__c,
                    Appointment_Confirmation_Type__c,
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

            if (matchingLeads.isEmpty()) {
                RestContext.response.statusCode = 404;

                response.success = false;
                response.message =
                    'Lead record was not found.';
                response.appointmentAvailable = false;

                return response;
            }

            Lead leadRecord = matchingLeads[0];

            Boolean appointmentAvailable =
                leadRecord.Appointment_Sent_date__c != null ||
                leadRecord.Appointment_Date__c != null ||
                String.isNotBlank(
                    leadRecord.Appointment_Time_Slots__c
                ) ||
                String.isNotBlank(
                    leadRecord.Appointment_Status__c
                );

            response.success = true;
            response.leadId = leadRecord.Id;
            response.appointmentAvailable =
                appointmentAvailable;

            response.availableTimeSlots =
                AVAILABLE_TIME_SLOTS;

            if (!appointmentAvailable) {
                RestContext.response.statusCode = 200;

                response.message =
                    'No site visit appointment has been scheduled yet.';

                response.actionRequired = false;

                return response;
            }

            String appointmentStatus =
                leadRecord.Appointment_Status__c;

            Boolean actionRequired =
                appointmentStatus == 'Pending' ||
                appointmentStatus ==
                    'Appointment Rescheduled';

            response.message =
                'Site visit appointment details loaded successfully.';

            response.actionRequired = actionRequired;

            response.appointmentType =
                leadRecord
                    .Appointment_Confirmation_Type__c;

            response.appointmentSentDate =
                formatDate(
                    leadRecord.Appointment_Sent_date__c
                );

            response.appointmentDate =
                formatDate(
                    leadRecord.Appointment_Date__c
                );

            response.appointmentTimeSlot =
                leadRecord.Appointment_Time_Slots__c;

            response.appointmentStatus =
                appointmentStatus;

            response.appointmentConfirmed =
                leadRecord.Appointment_Completed__c == true;

            response.requestedDate =
                formatDate(
                    leadRecord
                        .Appointment_Rescheduled_Time__c
                );

            response.requestedTimeSlot =
                leadRecord.Time_Slots__c;

            response.rejectionReason =
                leadRecord
                    .Appointment_Rejection_Reason__c;

            response.siteLocation =
                leadRecord.Site_Location__c;

            response.supervisorName =
                leadRecord.Supervisor_User__c == null
                    ? null
                    : leadRecord.Supervisor_User__r.Name;

            response.supervisorEmail =
                leadRecord.Supervisor_User_Email__c;

            response.supervisorPhone =
                leadRecord.Supervisor_User_Phone__c;

            /*
             * No dedicated supervisor-notes field currently exists.
             * Flutter will display its configured fallback message.
             */
            response.supervisorNotes = null;

            response.clientResponseMessage =
                getClientResponseMessage(
                    appointmentStatus
                );

            RestContext.response.statusCode = 200;

            return response;

        } catch (QueryException exceptionValue) {
            RestContext.response.statusCode = 404;

            response.success = false;
            response.appointmentAvailable = false;
            response.message =
                'Lead record was not found.';

            return response;

        } catch (Exception exceptionValue) {
            RestContext.response.statusCode = 500;

            response.success = false;
            response.appointmentAvailable = false;
            response.message =
                'Unable to load the site visit details. '
                + exceptionValue.getMessage();

            return response;
        }
    }

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

    private static String formatDate(
        Date dateValue
    ) {
        if (dateValue == null) {
            return null;
        }

        return String.valueOf(dateValue);
    }

    private static String getClientResponseMessage(
        String appointmentStatus
    ) {
        if (appointmentStatus == 'Approved') {
            return
                'You approved this site visit appointment.';
        }

        if (appointmentStatus == 'Rescheduled') {
            return
                'You requested a different site visit date and time.';
        }

        if (appointmentStatus == 'Rejected') {
            return
                'You rejected this site visit appointment.';
        }

        return null;
    }

    global class SiteVisitResponse {
        public Boolean success;
        public String message;

        public Boolean appointmentAvailable;
        public Boolean actionRequired;

        public Id leadId;

        public String appointmentType;
        public String appointmentSentDate;
        public String appointmentDate;
        public String appointmentTimeSlot;
        public String appointmentStatus;

        public Boolean appointmentConfirmed;

        public String requestedDate;
        public String requestedTimeSlot;
        public String rejectionReason;

        public String supervisorName;
        public String supervisorEmail;
        public String supervisorPhone;
        public String supervisorNotes;

        public String siteLocation;
        public String clientResponseMessage;

        public List<String> availableTimeSlots;

        public SiteVisitResponse() {
            success = false;
            appointmentAvailable = false;
            actionRequired = false;
            appointmentConfirmed = false;

            availableTimeSlots =
                new List<String>();
        }
    }
}