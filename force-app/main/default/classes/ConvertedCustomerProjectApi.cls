/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ConvertedCustomerProjectApi
 * Author          : <YourName>
 * Created Date    : Aug 13, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Aug 13, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Aug 13, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@RestResource(urlMapping='/converted-customer/project/*')
global without sharing class ConvertedCustomerProjectApi {
    private class SiteVisitContext {
        Id contactId;
        Id leadId;
        Id opportunityId;
    }

    @HttpGet
    global static void getProject() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            SiteVisitContext context = resolveSiteVisitContext(
                parseId(request.params.get('contactId'), '003'),
                parseId(request.params.get('leadId'), '00Q'),
                parseId(request.params.get('opportunityId'), '006')
            );
            Opportunity project = resolveOpportunity(context.contactId, context.leadId, context.opportunityId);
            if (project == null) {
                write(response, 404, new Map<String, Object>{
                    'success' => false,
                    'message' => 'No Opportunity is associated with this Contact or Lead.'
                });
                return;
            }

            String path = request.requestURI == null ? '' : request.requestURI.toLowerCase();
            if (path.endsWith('/site-visits')) {
                write(response, 200, siteVisitPayload(project, context));
            } else {
                write(response, 200, projectPayload(project));
            }
        } catch (Exception error) {
            write(response, 400, new Map<String, Object>{
                'success' => false,
                'message' => error.getMessage()
            });
        }
    }

    private static Opportunity resolveOpportunity(Id contactId, Id leadId, Id opportunityId) {
        String fields = 'Id, Name, AccountId, ContactId, Primary_Contact__c, Email__c, ' +
            'Lead_Name__c, Lead_Phone__c, Site_Space__c, Type_of_Project__c, ' +
            'Project_Type__c, Project_Scope__c, Plan_Level__c, Budget__c, ' +
            'Estimated_Budget__c, Site_Location__c, Project_Description__c, ' +
            'Appointment_Confirmation_Type__c, Appointment_Confirmed__c, ' +
            'Appointment_Date__c, Appointment_Status__c, Appointment_Time_Slots__c, ' +
            'Appointment_Rescheduled_Date__c, Rescheduled_Time_Slots__c, ' +
            'Site_Visit_Manager_Approval__c, Site_Visit_Status__c, Supervisor_Name__c, ' +
            'Supervisor_User__c, Supervisor_User_Email__c, Supervisor_User_Phone__c, ' +
            'Project_Estimated_Completion_Months__c, Supervisor_Estimated_Budget__c';

        if (opportunityId != null) {
            List<Opportunity> rows = Database.query(
                'SELECT ' + fields + ' FROM Opportunity WHERE Id = :opportunityId LIMIT 1'
            );
            return rows.isEmpty() ? null : rows[0];
        }

        if (leadId != null) {
            List<Lead> leadRows = [
                SELECT ConvertedOpportunityId
                FROM Lead
                WHERE Id = :leadId
                LIMIT 1
            ];
            if (!leadRows.isEmpty() && leadRows[0].ConvertedOpportunityId != null) {
                Id convertedOpportunityId = leadRows[0].ConvertedOpportunityId;
                List<Opportunity> rows = Database.query(
                    'SELECT ' + fields + ' FROM Opportunity WHERE Id = :convertedOpportunityId LIMIT 1'
                );
                if (!rows.isEmpty()) return rows[0];
            }
        }

        if (contactId == null) return null;

        List<Lead> converted = [
            SELECT ConvertedOpportunityId
            FROM Lead
            WHERE IsConverted = true AND ConvertedContactId = :contactId
            ORDER BY ConvertedDate DESC
            LIMIT 1
        ];
        if (!converted.isEmpty() && converted[0].ConvertedOpportunityId != null) {
            Id convertedOpportunityId = converted[0].ConvertedOpportunityId;
            List<Opportunity> rows = Database.query(
                'SELECT ' + fields + ' FROM Opportunity WHERE Id = :convertedOpportunityId LIMIT 1'
            );
            if (!rows.isEmpty()) return rows[0];
        }

        List<Opportunity> direct = Database.query(
            'SELECT ' + fields + ' FROM Opportunity ' +
            'WHERE Primary_Contact__c = :contactId OR ContactId = :contactId ' +
            'ORDER BY IsClosed ASC, LastModifiedDate DESC LIMIT 1'
        );
        return direct.isEmpty() ? null : direct[0];
    }

    private static Map<String, Object> projectPayload(Opportunity project) {
        return new Map<String, Object>{
            'success' => true,
            'projectSubmitted' => true,
            'opportunityId' => project.Id,
            'projectName' => project.Name,
            'firstName' => project.Lead_Name__c,
            'phone' => project.Lead_Phone__c,
            'email' => project.Email__c,
            'siteSpace' => project.Site_Space__c,
            'typeOfProject' => project.Type_of_Project__c,
            'projectType' => project.Project_Type__c,
            'projectScope' => project.Project_Scope__c,
            'planLevel' => project.Plan_Level__c,
            'customerBudget' => project.Budget__c == null ? project.Estimated_Budget__c : project.Budget__c,
            'siteLocation' => project.Site_Location__c,
            'projectDescription' => project.Project_Description__c
        };
    }

    private static Map<String, Object> siteVisitPayload(Opportunity project, SiteVisitContext context) {
        List<Map<String, Object>> reports = querySiteVisitReports(context);
        return new Map<String, Object>{
            'success' => true,
            'message' => reports.isEmpty() ? 'No Site Visit Report is linked to this Contact, its converted Leads, or Opportunities.': 'Site Visit Report loaded.',
            'leadId' => context.leadId,
            'opportunityId' => context.opportunityId == null ? project.Id : context.opportunityId,
            'appointmentAvailable' => project.Appointment_Date__c != null || project.Appointment_Status__c != null,
            'actionRequired' => project.Appointment_Confirmed__c != true,
            'appointmentConfirmed' => project.Appointment_Confirmed__c == true,
            'appointmentDate' => project.Appointment_Date__c,
            'appointmentTimeSlot' => project.Appointment_Time_Slots__c,
            'appointmentStatus' => project.Appointment_Status__c,
            'requestedDate' => project.Appointment_Rescheduled_Date__c,
            'requestedTimeSlot' => project.Rescheduled_Time_Slots__c,
            'siteVisitStatus' => project.Site_Visit_Status__c,
            'managementApproval' => project.Site_Visit_Manager_Approval__c,
            'supervisorName' => project.Supervisor_Name__c,
            'reports' => reports,
            'reportAvailable' => !reports.isEmpty(),
            'report' => reports.isEmpty() ? null : reports[0]
        };
    }

    private static List<Map<String, Object>> querySiteVisitReports(SiteVisitContext context) {
        Id resolvedLeadId = context == null ? null : context.leadId;
        Id resolvedOpportunityId = context == null ? null : context.opportunityId;

        if (resolvedLeadId == null && resolvedOpportunityId == null) {
            return new List<Map<String, Object>>();
        }

        List<Site_Visit_Report__c> rows;
        if (resolvedOpportunityId != null && resolvedLeadId != null) {
            rows = [
                SELECT Id, Name, Opportunity__c, Opportunity__r.Name, Lead__c, Lead__r.Name,
                    RecordTypeId, RecordType.Name, CreatedDate,
                    Site_Visit_Type__c, Project_Stage__c, Site_Visit_Date__c,
                    Site_Visit_Time_Slot__c, Site_Address__c, Description__c,
                    Site_Visit_Report_Status__c, Is_Final_Submitted__c, Management_Approval__c,
                    Total_Estimated_Cost__c, Estimated_Completion_Date__c,
                    Rooms_Count__c, Site_Area_Sq_Ft__c, Usable_Area_Sq_Ft__c,
                    Estimated_Budget_Description__c, Estimated_Completion_Months__c,
                    Negotiate__c, Negotation_Reason__c, Client_Approval__c,
                    Layout_Blueprint_Uploaded__c, Supervisor_User__r.Name
                FROM Site_Visit_Report__c
                WHERE Opportunity__c = :resolvedOpportunityId OR Lead__c = :resolvedLeadId
                ORDER BY CreatedDate DESC
            ];
        } else if (resolvedOpportunityId != null) {
            rows = [
                SELECT Id, Name, Opportunity__c, Opportunity__r.Name, Lead__c, Lead__r.Name,
                    RecordTypeId, RecordType.Name, CreatedDate,
                    Site_Visit_Type__c, Project_Stage__c, Site_Visit_Date__c,
                    Site_Visit_Time_Slot__c, Site_Address__c, Description__c,
                    Site_Visit_Report_Status__c, Is_Final_Submitted__c, Management_Approval__c,
                    Total_Estimated_Cost__c, Estimated_Completion_Date__c,
                    Rooms_Count__c, Site_Area_Sq_Ft__c, Usable_Area_Sq_Ft__c,
                    Estimated_Budget_Description__c, Estimated_Completion_Months__c,
                    Negotiate__c, Negotation_Reason__c, Client_Approval__c,
                    Layout_Blueprint_Uploaded__c, Supervisor_User__r.Name
                FROM Site_Visit_Report__c
                WHERE Opportunity__c = :resolvedOpportunityId
                ORDER BY CreatedDate DESC
            ];
        } else {
            rows = [
                SELECT Id, Name, Opportunity__c, Opportunity__r.Name, Lead__c, Lead__r.Name,
                    RecordTypeId, RecordType.Name, CreatedDate,
                    Site_Visit_Type__c, Project_Stage__c, Site_Visit_Date__c,
                    Site_Visit_Time_Slot__c, Site_Address__c, Description__c,
                    Site_Visit_Report_Status__c, Is_Final_Submitted__c, Management_Approval__c,
                    Total_Estimated_Cost__c, Estimated_Completion_Date__c,
                    Rooms_Count__c, Site_Area_Sq_Ft__c, Usable_Area_Sq_Ft__c,
                    Estimated_Budget_Description__c, Estimated_Completion_Months__c,
                    Negotiate__c, Negotation_Reason__c, Client_Approval__c,
                    Layout_Blueprint_Uploaded__c, Supervisor_User__r.Name
                FROM Site_Visit_Report__c
                WHERE Lead__c = :resolvedLeadId
                ORDER BY CreatedDate DESC
            ];
        }
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Site_Visit_Report__c row : rows) {
            results.add(new Map<String, Object>{
                'reportId' => row.Id,
                'reportName' => row.Name,
                'recordType' => row.RecordType == null ? null : row.RecordType.Name,
                'opportunityId' => row.Opportunity__c,
                'opportunityName' => row.Opportunity__r == null ? null : row.Opportunity__r.Name,
                'leadId' => row.Lead__c,
                'leadName' => row.Lead__r == null ? null : row.Lead__r.Name,
                'siteVisitType' => row.Site_Visit_Type__c,
                'projectStage' => row.Project_Stage__c,
                'siteVisitDate' => row.Site_Visit_Date__c,
                'siteVisitTimeSlot' => row.Site_Visit_Time_Slot__c,
                'siteAddress' => row.Site_Address__c,
                'description' => row.Description__c,
                'status' => row.Site_Visit_Report_Status__c,
                'finalSubmitted' => row.Is_Final_Submitted__c,
                'managementApproval' => row.Management_Approval__c,
                'totalEstimatedCost' => row.Total_Estimated_Cost__c,
                'estimatedCompletionDate' => row.Estimated_Completion_Date__c,
                'roomsCount' => row.Rooms_Count__c,
                'siteAreaSqFt' => row.Site_Area_Sq_Ft__c,
                'usableAreaSqFt' => row.Usable_Area_Sq_Ft__c,
                'estimatedBudgetDescription' => row.Estimated_Budget_Description__c,
                'estimatedCompletionMonths' => row.Estimated_Completion_Months__c,
                'reviewChanges' => row.Negotiate__c,
                'reviewChangeReason' => row.Negotation_Reason__c,
                'clientApproval' => row.Client_Approval__c,
                'layoutBlueprintUploaded' => row.Layout_Blueprint_Uploaded__c,
                'supervisorName' => row.Supervisor_User__r == null ? null : row.Supervisor_User__r.Name
            });
        }
        return results;
    }

    private static SiteVisitContext resolveSiteVisitContext(Id contactId, Id leadId, Id opportunityId) {
        SiteVisitContext context = new SiteVisitContext();
        context.contactId = contactId;
        context.leadId = leadId;
        context.opportunityId = opportunityId;

        if (context.leadId != null || context.contactId != null || context.opportunityId != null) {
            List<Lead> leadRows;
            if (context.leadId != null) {
                leadRows = [
                    SELECT Id, ConvertedContactId, ConvertedOpportunityId
                    FROM Lead
                    WHERE Id = :context.leadId
                    LIMIT 1
                ];
            } else if (context.opportunityId != null) {
                leadRows = [
                    SELECT Id, ConvertedContactId, ConvertedOpportunityId
                    FROM Lead
                    WHERE IsConverted = true AND ConvertedOpportunityId = :context.opportunityId
                    ORDER BY ConvertedDate DESC
                    LIMIT 1
                ];
            } else {
                leadRows = [
                    SELECT Id, ConvertedContactId, ConvertedOpportunityId
                    FROM Lead
                    WHERE IsConverted = true AND ConvertedContactId = :context.contactId
                    ORDER BY ConvertedDate DESC
                    LIMIT 1
                ];
            }

            if (!leadRows.isEmpty()) {
                Lead sourceLead = leadRows[0];
                context.leadId = sourceLead.Id;
                if (context.contactId == null) context.contactId = sourceLead.ConvertedContactId;
                if (context.opportunityId == null) context.opportunityId = sourceLead.ConvertedOpportunityId;
            }
        }

        return context;
    }

    private static Id parseId(String value, String prefix) {
        if (String.isBlank(value) || !value.startsWith(prefix)) return null;
        return (Id)value;
    }

    private static void write(RestResponse response, Integer statusCode, Object payload) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}