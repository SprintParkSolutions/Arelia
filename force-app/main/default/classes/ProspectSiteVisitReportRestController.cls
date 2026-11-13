/**
 * Returns a management-approved Lead Site Visit Report
 * and the files linked directly to that report.
 *
 * Report endpoint:
 * /services/apexrest/registration/lead/site-visit-report
 *
 * Profile report request:
 * ?leadId=00Q...
 *
 * Specific report request:
 * ?leadId=00Q...&reportId=a1C...
 *
 * Document request:
 * ?leadId=00Q...&reportId=a1C...&versionId=068...
 */
@RestResource(
    urlMapping='/registration/lead/site-visit-report/*'
)
global without sharing class ProspectSiteVisitReportRestController {

    /**
     * Returns the approved report JSON or one linked document.
     */
    @HttpGet
    global static void getReportOrDocument() {
        RestResponse responseValue = RestContext.response;

        try {
            applyNoCacheHeaders(responseValue);

            RestRequest requestValue = RestContext.request;

            String leadIdValue = getParameter(
                requestValue,
                'leadId'
            );

            String reportIdValue = getParameter(
                requestValue,
                'reportId'
            );

            String versionIdValue = getParameter(
                requestValue,
                'versionId'
            );

            System.debug(
                LoggingLevel.INFO,
                'SITE VISIT REPORT API REQUEST - ' +
                'Lead ID: ' +
                leadIdValue +
                ', Report ID: ' +
                reportIdValue +
                ', Version ID: ' +
                versionIdValue
            );

            Id leadId = parseId(
                leadIdValue,
                Lead.SObjectType,
                'Valid Lead ID is required.'
            );

            Site_Visit_Report__c reportRecord;

            /*
             * Profile/Drawer flow:
             * leadId only -> latest final-submitted and
             * management-approved report.
             *
             * Notification flow:
             * leadId + reportId -> specified report.
             */
            if (String.isBlank(reportIdValue)) {
                if (String.isNotBlank(versionIdValue)) {
                    throw new RequestValidationException(
                        'Valid Site Visit Report ID is required '
                        + 'to open a report document.'
                    );
                }

                reportRecord =
                    getLatestApprovedReport(
                        leadId
                    );
            } else {
                Id reportId = parseId(
                    reportIdValue,
                    Site_Visit_Report__c.SObjectType,
                    'Valid Site Visit Report ID is required.'
                );

                reportRecord =
                    getApprovedReport(
                        leadId,
                        reportId
                    );
            }

            if (String.isNotBlank(versionIdValue)) {
                Id versionId = parseId(
                    versionIdValue,
                    ContentVersion.SObjectType,
                    'Valid Content Version ID is required.'
                );

                writeDocument(
                    responseValue,
                    reportRecord,
                    versionId
                );

                return;
            }

            writeReportJson(
                responseValue,
                reportRecord
            );
        } catch (
            RequestValidationException exceptionValue
        ) {
            writeError(
                responseValue,
                400,
                exceptionValue.getMessage()
            );
        } catch (
            ReportNotFoundException exceptionValue
        ) {
            writeError(
                responseValue,
                404,
                exceptionValue.getMessage()
            );
        } catch (Exception exceptionValue) {
            System.debug(
                LoggingLevel.ERROR,
                'Site Visit Report REST error: ' +
                exceptionValue.getMessage() +
                '\n' +
                exceptionValue.getStackTraceString()
            );

            writeError(
                responseValue,
                500,
                'Unable to load the Site Visit Report.'
            );
        }
    }

    /**
     * Loads the latest final-submitted and management-approved
     * Site Visit Report for the logged-in Prospect Lead.
     *
     * @param leadId Logged-in Prospect Lead ID.
     * @return Latest management-approved report.
     */
    private static Site_Visit_Report__c
        getLatestApprovedReport(
            Id leadId
        ) {
        System.debug(
            LoggingLevel.INFO,
            'LATEST SITE VISIT REPORT QUERY - Lead ID: ' +
            String.valueOf(leadId)
        );

        List<Site_Visit_Report__c> reportRecords = [
            SELECT
                Id,
                Name,
                Client_Approval__c,
                Description__c,
                Estimated_Budget_Description__c,
                Estimated_Completion_Date__c,
                Estimated_Completion_Months__c,
                Is_Final_Submitted__c,
                Layout_Blueprint_Uploaded__c,
                Lead__c,
                Management_Approval__c,
                Negotation_Reason__c,
                Negotiate__c,
                Project_Stage__c,
                Rooms_Count__c,
                Site_Address__c,
                Site_Area_Sq_Ft__c,
                Site_Visit_Date__c,
                Site_Visit_Report_Status__c,
                Site_Visit_Time_Slot__c,
                Site_Visit_Type__c,
                Supervisor_User__c,
                Supervisor_User__r.FirstName,
                Supervisor_User__r.LastName,
                Total_Estimated_Cost__c,
                Usable_Area_Sq_Ft__c,
                Wizard_Step__c,
                Opportunity__c,
                RecordType.Name
            FROM Site_Visit_Report__c
            WHERE Lead__c = :leadId
            AND Is_Final_Submitted__c = true
            AND Management_Approval__c = true
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (reportRecords.isEmpty()) {
            throw new ReportNotFoundException(
                'No final-submitted and management-approved '
                + 'Site Visit Report is available yet.'
            );
        }

        return reportRecords[0];
    }

    /**
     * Loads the report by ID first and then validates
     * the Lead and approval conditions separately.
     *
     * @param leadId Logged-in Prospect Lead ID.
     * @param reportId Site Visit Report ID.
     * @return Valid management-approved report.
     */
    private static Site_Visit_Report__c getApprovedReport(
        Id leadId,
        Id reportId
    ) {
        System.debug(
            LoggingLevel.INFO,
            'SITE VISIT REPORT QUERY - ' +
            'Lead ID: ' +
            String.valueOf(leadId) +
            ', Report ID: ' +
            String.valueOf(reportId)
        );

        List<Site_Visit_Report__c> reportRecords = [
            SELECT
                Id,
                Name,
                Client_Approval__c,
                Description__c,
                Estimated_Budget_Description__c,
                Estimated_Completion_Date__c,
                Estimated_Completion_Months__c,
                Is_Final_Submitted__c,
                Layout_Blueprint_Uploaded__c,
                Lead__c,
                Management_Approval__c,
                Negotation_Reason__c,
                Negotiate__c,
                Project_Stage__c,
                Rooms_Count__c,
                Site_Address__c,
                Site_Area_Sq_Ft__c,
                Site_Visit_Date__c,
                Site_Visit_Report_Status__c,
                Site_Visit_Time_Slot__c,
                Site_Visit_Type__c,
                Supervisor_User__c,
                Supervisor_User__r.FirstName,
                Supervisor_User__r.LastName,
                Total_Estimated_Cost__c,
                Usable_Area_Sq_Ft__c,
                Wizard_Step__c,
                Opportunity__c,
                RecordType.Name
            FROM Site_Visit_Report__c
            WHERE Id = :reportId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (reportRecords.isEmpty()) {
            throw new ReportNotFoundException(
                'Site Visit Report ID was not found in the Dev4 org.'
            );
        }

        Site_Visit_Report__c reportRecord =
            reportRecords[0];

        System.debug(
            LoggingLevel.INFO,
            'SITE VISIT REPORT FOUND - ' +
            'Report ID: ' +
            String.valueOf(reportRecord.Id) +
            ', Lead ID: ' +
            String.valueOf(reportRecord.Lead__c) +
            ', Final Submitted: ' +
            String.valueOf(
                reportRecord.Is_Final_Submitted__c
            ) +
            ', Management Approval: ' +
            String.valueOf(
                reportRecord.Management_Approval__c
            ) +
            ', Status: ' +
            String.valueOf(
                reportRecord.Site_Visit_Report_Status__c
            )
        );

        if (reportRecord.Lead__c == null) {
            throw new ReportNotFoundException(
                'The Site Visit Report is not linked to a Lead.'
            );
        }

        if (reportRecord.Lead__c != leadId) {
            throw new ReportNotFoundException(
                'The Site Visit Report does not belong '
                + 'to the logged-in Prospect.'
            );
        }

        if (
            reportRecord.Is_Final_Submitted__c != true
        ) {
            throw new ReportNotFoundException(
                'The Site Visit Report is not final submitted.'
            );
        }

        if (
            reportRecord.Management_Approval__c != true
        ) {
            throw new ReportNotFoundException(
                'The Site Visit Report is not approved by management.'
            );
        }

        return reportRecord;
    }

    /**
     * Returns report fields and linked-document metadata.
     *
     * @param responseValue REST response.
     * @param reportRecord Approved Site Visit Report.
     */
    private static void writeReportJson(
        RestResponse responseValue,
        Site_Visit_Report__c reportRecord
    ) {
        List<Object> documents =
            new List<Object>();

        List<ContentDocumentLink> documentLinks = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileExtension,
                ContentDocument.ContentSize,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :reportRecord.Id
            WITH SYSTEM_MODE
            ORDER BY ContentDocument.Title
        ];

        for (
            ContentDocumentLink linkRecord :
            documentLinks
        ) {
            String extensionValue =
                normalizeExtension(
                    linkRecord.ContentDocument
                        .FileExtension
                );

            documents.add(
                new Map<String, Object>{
                    'documentId' =>
                        linkRecord.ContentDocumentId,
                    'versionId' =>
                        linkRecord.ContentDocument
                            .LatestPublishedVersionId,
                    'title' =>
                        linkRecord.ContentDocument.Title,
                    'fileExtension' =>
                        extensionValue,
                    'contentSize' =>
                        linkRecord.ContentDocument
                            .ContentSize,
                    'isImage' =>
                        isImageExtension(
                            extensionValue
                        )
                }
            );
        }

        Map<String, Object> reportData =
            new Map<String, Object>{
                'reportId' =>
                    reportRecord.Id,

                'reportName' =>
                    reportRecord.Name,

                'recordType' =>
                    reportRecord.RecordType == null
                        ? null
                        : reportRecord.RecordType.Name,

                'leadId' =>
                    reportRecord.Lead__c,

                'opportunityId' =>
                    reportRecord.Opportunity__c,

                'siteVisitType' =>
                    reportRecord.Site_Visit_Type__c,

                'projectStage' =>
                    reportRecord.Project_Stage__c,

                'siteVisitDate' =>
                    reportRecord.Site_Visit_Date__c,

                'siteVisitTimeSlot' =>
                    reportRecord.Site_Visit_Time_Slot__c,

                'siteAddress' =>
                    reportRecord.Site_Address__c,

                'roomsCount' =>
                    reportRecord.Rooms_Count__c,

                'siteAreaSqFt' =>
                    reportRecord.Site_Area_Sq_Ft__c,

                'usableAreaSqFt' =>
                    reportRecord.Usable_Area_Sq_Ft__c,

                'description' =>
                    reportRecord.Description__c,

                'estimatedBudgetDescription' =>
                    reportRecord
                        .Estimated_Budget_Description__c,

                'estimatedCompletionDate' =>
                    reportRecord
                        .Estimated_Completion_Date__c,

                'estimatedCompletionMonths' =>
                    reportRecord
                        .Estimated_Completion_Months__c,

                'totalEstimatedCost' =>
                    reportRecord.Total_Estimated_Cost__c,

                'status' =>
                    reportRecord
                        .Site_Visit_Report_Status__c,

                'supervisorId' =>
                    reportRecord.Supervisor_User__c,

                // 'supervisorName' =>
                //     reportRecord.Supervisor_User__r ==
                //             null
                //         ? null
                //         : reportRecord
                //             .Supervisor_User__r.Name,

                'supervisorName' =>
                reportRecord.Supervisor_User__r == null
                    ? null
                    : (
                        String.isBlank(
                            reportRecord.Supervisor_User__r.FirstName
                        )
                            ? reportRecord.Supervisor_User__r.LastName
                            : reportRecord.Supervisor_User__r.FirstName +
                            (
                                String.isBlank(
                                    reportRecord.Supervisor_User__r.LastName
                                )
                                    ? ''
                                    : ' ' +
                                        reportRecord.Supervisor_User__r.LastName
                            )
                    ),

                'layoutBlueprintUploaded' =>
                    reportRecord
                        .Layout_Blueprint_Uploaded__c,

                'reviewChanges' =>
                    reportRecord.Negotiate__c,

                'reviewChangeReason' =>
                    reportRecord.Negotation_Reason__c,

                'clientApproval' =>
                    reportRecord.Client_Approval__c,

                'finalSubmitted' =>
                    reportRecord.Is_Final_Submitted__c,

                'managementApproval' =>
                    reportRecord.Management_Approval__c,

                'wizardStep' =>
                    reportRecord.Wizard_Step__c
            };

        Map<String, Object> responseBody =
            new Map<String, Object>{
                'success' => true,
                'reportAvailable' => true,
                'message' =>
                    'Site Visit Report loaded successfully.',
                'report' => reportData,
                'documents' => documents
            };

        responseValue.statusCode = 200;

        applyNoCacheHeaders(
            responseValue
        );

        responseValue.addHeader(
            'Content-Type',
            'application/json; charset=UTF-8'
        );

        responseValue.responseBody =
            Blob.valueOf(
                JSON.serialize(
                    responseBody
                )
            );
    }

    /**
     * Streams a ContentVersion linked directly
     * to the Site Visit Report.
     *
     * @param responseValue REST response.
     * @param reportRecord Site Visit Report.
     * @param versionId ContentVersion ID.
     */
    private static void writeDocument(
        RestResponse responseValue,
        Site_Visit_Report__c reportRecord,
        Id versionId
    ) {
        Boolean versionLinkedToReport = false;

        List<ContentDocumentLink> documentLinks = [
            SELECT
                ContentDocumentId,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :reportRecord.Id
            WITH SYSTEM_MODE
        ];

        for (
            ContentDocumentLink linkRecord :
            documentLinks
        ) {
            if (
                linkRecord.ContentDocument
                    .LatestPublishedVersionId ==
                    versionId
            ) {
                versionLinkedToReport = true;
                break;
            }
        }

        if (!versionLinkedToReport) {
            throw new ReportNotFoundException(
                'The requested document is not linked to this report.'
            );
        }

        List<ContentVersion> versionRecords = [
            SELECT
                Id,
                Title,
                FileExtension,
                VersionData
            FROM ContentVersion
            WHERE Id = :versionId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (versionRecords.isEmpty()) {
            throw new ReportNotFoundException(
                'The requested document was not found.'
            );
        }

        ContentVersion versionRecord =
            versionRecords[0];

        String extensionValue =
            normalizeExtension(
                versionRecord.FileExtension
            );

        String fileName =
            versionRecord.Title;

        if (String.isNotBlank(extensionValue)) {
            fileName += '.' + extensionValue;
        }

        fileName = fileName.replace(
            '"',
            ''
        );

        responseValue.statusCode = 200;

        applyNoCacheHeaders(
            responseValue
        );

        responseValue.addHeader(
            'Content-Type',
            getMimeType(extensionValue)
        );

        responseValue.addHeader(
            'Content-Disposition',
            'inline; filename="' +
            fileName +
            '"'
        );

        responseValue.responseBody =
            versionRecord.VersionData;
    }

    /**
     * Gets one URL query parameter.
     *
     * @param requestValue REST request.
     * @param parameterName Parameter name.
     * @return Parameter value.
     */
    private static String getParameter(
        RestRequest requestValue,
        String parameterName
    ) {
        if (
            requestValue == null ||
            requestValue.params == null
        ) {
            return null;
        }

        return requestValue.params.get(
            parameterName
        );
    }

    /**
     * Converts a String to an ID and validates its object type.
     *
     * @param rawValue Raw ID value.
     * @param expectedType Expected Salesforce object type.
     * @param errorMessage Validation error message.
     * @return Parsed Salesforce ID.
     */
    private static Id parseId(
        String rawValue,
        Schema.SObjectType expectedType,
        String errorMessage
    ) {
        if (String.isBlank(rawValue)) {
            throw new RequestValidationException(
                errorMessage
            );
        }

        try {
            Id parsedId =
                (Id) rawValue.trim();

            if (
                parsedId.getSObjectType() !=
                expectedType
            ) {
                throw new RequestValidationException(
                    errorMessage
                );
            }

            return parsedId;
        } catch (
            RequestValidationException exceptionValue
        ) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            throw new RequestValidationException(
                errorMessage
            );
        }
    }

    /**
     * Normalizes a file extension.
     *
     * @param extensionValue File extension.
     * @return Lowercase extension.
     */
    private static String normalizeExtension(
        String extensionValue
    ) {
        return String.isBlank(extensionValue)
            ? ''
            : extensionValue
                .trim()
                .toLowerCase();
    }

    /**
     * Checks whether a file extension represents an image.
     *
     * @param extensionValue Lowercase file extension.
     * @return True when the file is an image.
     */
    private static Boolean isImageExtension(
        String extensionValue
    ) {
        return new Set<String>{
            'jpg',
            'jpeg',
            'png',
            'gif',
            'webp',
            'bmp'
        }.contains(extensionValue);
    }

    /**
     * Returns the MIME type for a file extension.
     *
     * @param extensionValue Lowercase file extension.
     * @return MIME type.
     */
    private static String getMimeType(
        String extensionValue
    ) {
        Map<String, String> mimeTypes =
            new Map<String, String>{
                'pdf' =>
                    'application/pdf',

                'jpg' =>
                    'image/jpeg',

                'jpeg' =>
                    'image/jpeg',

                'png' =>
                    'image/png',

                'gif' =>
                    'image/gif',

                'webp' =>
                    'image/webp',

                'bmp' =>
                    'image/bmp',

                'txt' =>
                    'text/plain',

                'csv' =>
                    'text/csv',

                'doc' =>
                    'application/msword',

                'docx' =>
                    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',

                'xls' =>
                    'application/vnd.ms-excel',

                'xlsx' =>
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            };

        return mimeTypes.containsKey(
            extensionValue
        )
            ? mimeTypes.get(
                extensionValue
            )
            : 'application/octet-stream';
    }

    /**
     * Adds headers to prevent an old API response
     * from being cached.
     *
     * @param responseValue REST response.
     */
    private static void applyNoCacheHeaders(
        RestResponse responseValue
    ) {
        if (responseValue == null) {
            return;
        }

        responseValue.addHeader(
            'Cache-Control',
            'no-store, no-cache, must-revalidate, max-age=0'
        );

        responseValue.addHeader(
            'Pragma',
            'no-cache'
        );

        responseValue.addHeader(
            'Expires',
            '0'
        );
    }

    /**
     * Writes a standard JSON error response.
     *
     * @param responseValue REST response.
     * @param statusCode HTTP status code.
     * @param message Error message.
     */
    private static void writeError(
        RestResponse responseValue,
        Integer statusCode,
        String message
    ) {
        responseValue.statusCode =
            statusCode;

        applyNoCacheHeaders(
            responseValue
        );

        responseValue.addHeader(
            'Content-Type',
            'application/json; charset=UTF-8'
        );

        responseValue.responseBody =
            Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'success' => false,
                        'reportAvailable' => false,
                        'message' => message
                    }
                )
            );
    }

    /**
     * Request parameter validation exception.
     */
    private class RequestValidationException
        extends Exception {
    }

    /**
     * Report or document not-found exception.
     */
    private class ReportNotFoundException
        extends Exception {
    }
}