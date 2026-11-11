@RestResource(
    urlMapping='/registration/lead/project-status/*'
)
global without sharing class ProspectProjectStatusMobileController {

    /*
     * =========================================================
     * GET PROJECT STATUS
     * =========================================================
     */
    @HttpGet
    global static void getProjectStatus() {

        try {

            RestRequest request =
                RestContext.request;

            String leadId =
                request.params.get(
                    'leadId'
                );


            /*
             * =================================================
             * VALIDATE LEAD ID
             * =================================================
             */
            if (String.isBlank(leadId)) {

                writeError(
                    400,
                    'leadId is required.'
                );

                return;
            }


            Id normalizedLeadId;

            try {

                normalizedLeadId =
                    (Id) leadId.trim();

            } catch (Exception e) {

                writeError(
                    400,
                    'Invalid Lead ID.'
                );

                return;
            }


            /*
             * =================================================
             * FIND CONVERTED LEAD
             * =================================================
             *
             * Existing Project relationship:
             *
             * Project__c.Client__c
             *         ↓
             *      Contact
             *
             * Therefore we use ConvertedContactId.
             */
            List<Lead> leads =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'IsConverted, ' +
                        'ConvertedContactId, ' +
                        'ConvertedOpportunityId ' +
                    'FROM Lead ' +
                    'WHERE Id = :normalizedLeadId ' +
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


            if (!prospectLead.IsConverted) {

                writeError(
                    403,
                    'Your project is not available yet.'
                );

                return;
            }


            if (
                prospectLead.ConvertedContactId ==
                null
            ) {

                writeError(
                    403,
                    'This prospect is not connected to a client Contact.'
                );

                return;
            }


            Id contactId =
                prospectLead.ConvertedContactId;

            // Resolve the Opportunity from the selected Lead,
            // not from a client-supplied Opportunity ID.
            Id opportunityId = prospectLead.ConvertedOpportunityId;

            if (opportunityId == null) {
                writeError(
                    404,
                    'No Opportunity is linked to this project request.'
                );
                return;
            }


            /*
             * =================================================
             * FIND PROJECT FOR SELECTED OPPORTUNITY
             * =================================================
             *
             * Match both the selected Lead's converted Opportunity
             * and Contact. Never choose an arbitrary latest project.
             */
            List<Project__c> projects =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'Name, ' +
                        'Status__c, ' +
                        'Supervisor_Estimated_Budget__c, ' +
                        'Start_Date__c, ' +
                        'Estimated_End_Date__c, ' +
                        'Project_Completion_Status__c, ' +
                        'Client__c, ' +
                        'Project_Name__c, ' +
                        'Type_Of_Project__c, ' +
                        'Interior_Project_Type__r.Name ' +
                    'FROM Project__c ' +
                    'WHERE Client__c = :contactId ' +
                    'AND Project_Name__c = :opportunityId ' +
                    'LIMIT 1',
                    AccessLevel.SYSTEM_MODE
                );


            if (projects.isEmpty()) {

                writeError(
                    404,
                    'No Project is linked to the selected Opportunity yet.'
                );

                return;
            }


            Project__c project =
                projects[0];


            /*
             * =================================================
             * GET VENDOR ASSIGNMENTS
             * =================================================
             */
            Id projectId =
                project.Id;


            List<Vendor_Assignment__c>
                vendorAssignments =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'Vendor__r.Name, ' +
                        'Vendor_Category__c, ' +
                        'Completion__c, ' +
                        'Vendor_Work_Start_Date__c, ' +
                        'Vendor_Work_End_Date__c, ' +
                        'Vendor_Tasks_Remaining_Percentage__c, ' +
                        'Status__c, ' +
                        'Project__c ' +
                    'FROM Vendor_Assignment__c ' +
                    'WHERE Project__c = :projectId ' +
                    'ORDER BY CreatedDate ASC',
                    AccessLevel.SYSTEM_MODE
                );


            /*
             * =================================================
             * BUILD VENDOR RESPONSE
             * =================================================
             */
            List<Object> vendors =
                new List<Object>();


            for (
                Vendor_Assignment__c assignment :
                vendorAssignments
            ) {

                Map<String, Object> vendor =
                    new Map<String, Object>();


                vendor.put(
                    'vendorName',
                    assignment.Vendor__r == null
                        ? null
                        : assignment.Vendor__r.Name
                );


                vendor.put(
                    'vendorCategory',
                    assignment
                        .Vendor_Category__c == null
                        ? null
                        : String.valueOf(
                            assignment
                                .Vendor_Category__c
                        )
                );


                vendor.put(
                    'completionPercentage',
                    assignment
                        .Completion__c
                );


                vendor.put(
                    'startDate',
                    assignment
                        .Vendor_Work_Start_Date__c
                );


                vendor.put(
                    'endDate',
                    assignment
                        .Vendor_Work_End_Date__c
                );


                vendor.put(
                    'remainingTasks',
                    assignment
                        .Vendor_Tasks_Remaining_Percentage__c
                );


                vendor.put(
                    'status',
                    assignment.Status__c
                );


                vendors.add(
                    vendor
                );
            }


            /*
             * =================================================
             * PROJECT TYPE
             * =================================================
             */
            String projectType;


            if (
                !String.isBlank(
                    project.Type_Of_Project__c
                )
            ) {

                projectType =
                    project.Type_Of_Project__c;

            } else if (
                project.Interior_Project_Type__r
                != null
            ) {

                projectType =
                    project
                        .Interior_Project_Type__r
                        .Name;
            }


            /*
             * =================================================
             * PROJECT RESPONSE
             * =================================================
             */
            Map<String, Object> projectData =
                new Map<String, Object>();


            projectData.put(
                'projectId',
                project.Id
            );


            projectData.put(
                'projectName',
                project.Name
            );


            projectData.put(
                'projectStatus',
                project.Status__c
            );


            projectData.put(
                'projectType',
                projectType
            );


            projectData.put(
                'budget',
                project
                    .Supervisor_Estimated_Budget__c
            );


            projectData.put(
                'startDate',
                project.Start_Date__c
            );


            projectData.put(
                'endDate',
                project
                    .Estimated_End_Date__c
            );


            projectData.put(
                'completionPercentage',
                project
                    .Project_Completion_Status__c
            );


            projectData.put(
                'vendors',
                vendors
            );


            /*
             * =================================================
             * FINAL RESPONSE
             * =================================================
             */
            Map<String, Object> response =
                new Map<String, Object>();


            response.put(
                'success',
                true
            );


            response.put(
                'message',
                'Success'
            );


            response.put(
                'leadId',
                prospectLead.Id
            );


            response.put(
                'contactId',
                contactId
            );


            response.put(
                'projectAvailable',
                true
            );


            response.put(
                'project',
                projectData
            );


            writeJson(
                200,
                response
            );

        } catch (Exception e) {

            writeError(
                500,
                'Unable to load Project Status: ' +
                e.getMessage()
            );
        }
    }


    /*
     * =========================================================
     * ERROR RESPONSE
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
            'projectAvailable',
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
     * JSON RESPONSE
     * =========================================================
     */
    private static void writeJson(
        Integer statusCode,
        Object body
    ) {

        RestResponse response =
            RestContext.response;


        response.statusCode =
            statusCode;


        response.addHeader(
            'Content-Type',
            'application/json'
        );


        response.responseBody =
            Blob.valueOf(
                JSON.serialize(
                    body
                )
            );
    }
}