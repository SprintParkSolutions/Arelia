@RestResource(urlMapping='/registration/lead/architecture-design/*')
global without sharing class ArchitectureDesignMobileApi {

    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_CHANGES_REQUESTED =
        'Changes Requested';


    // =========================================================
    // REQUEST
    // =========================================================

    global class DecisionRequest {
        public Id leadId;
        public Id opportunityId;
        public Id designId;
        public String status;
        public String comments;
    }


    // =========================================================
    // INTERNAL CONTEXT
    // =========================================================

    private class ProspectContext {
        public Id leadId;
        public Id opportunityId;
    }


    // =========================================================
    // GET
    //
    // GET designs:
    // /services/apexrest/registration/lead/architecture-design/?leadId=00Q...
    //
    // GET specific design:
    // /services/apexrest/registration/lead/architecture-design/
    // ?leadId=00Q...&designId=a0...
    //
    // GET file:
    // /services/apexrest/registration/lead/architecture-design/file
    // ?leadId=00Q...&opportunityId=006...&designId=a0...&versionId=068...
    // =========================================================

    @HttpGet
    global static void doGet() {

        try {

            RestRequest request =
                RestContext.request;


            String requestUri =
                request.requestURI == null
                    ? ''
                    : request.requestURI.toLowerCase();


            // =================================================
            // FILE REQUEST
            // =================================================

            if (requestUri.endsWith('/file')) {

                serveFile();

                return;
            }


            // =================================================
            // PARAMETERS
            // =================================================

            Id leadId =
                parseId(
                    request.params.get(
                        'leadId'
                    )
                );


            Id requestedOpportunityId =
                parseId(
                    request.params.get(
                        'opportunityId'
                    )
                );


            Id requestedDesignId =
                parseId(
                    request.params.get(
                        'designId'
                    )
                );


            if (leadId == null) {

                writeError(
                    400,
                    'Salesforce Lead ID is required.'
                );

                return;
            }


            // =================================================
            // RESOLVE CONVERTED LEAD
            // =================================================

            ProspectContext prospect =
                resolveProspectContext(
                    leadId
                );


            if (prospect == null) {

                writeError(
                    404,
                    'This prospect has not been converted to an Opportunity yet.'
                );

                return;
            }


            Id opportunityId =
                prospect.opportunityId;


            // =================================================
            // VALIDATE OPPORTUNITY
            // =================================================

            if (
                requestedOpportunityId != null &&
                requestedOpportunityId !=
                    opportunityId
            ) {

                writeError(
                    403,
                    'You are not authorized to access this Opportunity.'
                );

                return;
            }


            // =================================================
            // GET DESIGNS
            // =================================================

            List<Architecture_Design__c> designs;


            if (
                requestedDesignId != null
            ) {

                designs = [
        SELECT
            Id,
            Name,
            Opportunity__c,
            Opportunity__r.Name,
            Status__c,
            Comments__c,
            External_File_Link__c,
            CreatedDate
        FROM Architecture_Design__c
        WHERE Id = :requestedDesignId
        AND Opportunity__c = :opportunityId
        ORDER BY CreatedDate DESC
    ];

            } else {

                designs = [
        SELECT
            Id,
            Name,
            Opportunity__c,
            Opportunity__r.Name,
            Status__c,
            Comments__c,
            External_File_Link__c,
            CreatedDate
        FROM Architecture_Design__c
        WHERE Opportunity__c = :opportunityId
        ORDER BY CreatedDate DESC
    ];
            }


            // =================================================
            // DESIGN IDS
            // =================================================

            Set<Id> designIds =
                new Set<Id>();


            for (
                Architecture_Design__c design :
                designs
            ) {

                designIds.add(
                    design.Id
                );
            }


            // =================================================
            // FILES BY DESIGN
            // =================================================

            Map<Id, List<Object>> filesByDesign =
                new Map<Id, List<Object>>();


            if (
                !designIds.isEmpty()
            ) {

                List<ContentDocumentLink> links = [
                    SELECT
                        LinkedEntityId,
                        ContentDocumentId,
                        ContentDocument.Title,
                        ContentDocument.FileExtension,
                        ContentDocument.LatestPublishedVersionId
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId IN :designIds
                ];


                for (
                    ContentDocumentLink link :
                    links
                ) {

                    if (
                        !filesByDesign.containsKey(
                            link.LinkedEntityId
                        )
                    ) {

                        filesByDesign.put(
                            link.LinkedEntityId,
                            new List<Object>()
                        );
                    }


                    Map<String, Object> fileData =
                        new Map<String, Object>();


                    fileData.put(
                        'versionId',
                        link.ContentDocument.LatestPublishedVersionId
                    );


                    fileData.put(
                        'title',
                        link.ContentDocument.Title
                    );


                    fileData.put(
                        'extension',
                        link.ContentDocument.FileExtension
                    );


                    fileData.put(
                        'contentType',
                        getContentType(
                            link.ContentDocument.FileExtension
                        )
                    );


                    filesByDesign.get(
                        link.LinkedEntityId
                    ).add(
                        fileData
                    );
                }
            }


            // =================================================
            // BUILD DESIGN RESPONSE
            // =================================================

            List<Object> designResponse =
                new List<Object>();


            for (
                Architecture_Design__c design :
                designs
            ) {

                Map<String, Object> item =
                    new Map<String, Object>();


                item.put(
                    'designId',
                    design.Id
                );


                item.put(
                    'designName',
                    design.Name
                );


                item.put(
                    'opportunityId',
                    design.Opportunity__c
                );


                item.put(
                    'opportunityName',
                    design.Opportunity__r == null
                        ? null
                        : design.Opportunity__r.Name
                );


                item.put(
                    'status',
                    design.Status__c
                );


                item.put(
                    'comments',
                    design.Comments__c
                );

item.put(
    'externalFileLink',
    design.External_File_Link__c
);
                item.put(
                    'createdDate',
                    design.CreatedDate
                );




                Boolean actionAllowed =
                    design.Status__c ==
                        STATUS_SENT;


                item.put(
                    'canApprove',
                    actionAllowed
                );


                item.put(
                    'canRequestChanges',
                    actionAllowed
                );


                if (
                    filesByDesign.containsKey(
                        design.Id
                    )
                ) {

                    item.put(
                        'files',
                        filesByDesign.get(
                            design.Id
                        )
                    );

                } else {

                    item.put(
                        'files',
                        new List<Object>()
                    );
                }


                designResponse.add(
                    item
                );
            }


            // =================================================
            // RESPONSE DATA
            // =================================================

            Map<String, Object> data =
                new Map<String, Object>();


            data.put(
                'leadId',
                prospect.leadId
            );


            data.put(
                'opportunityId',
                opportunityId
            );


            data.put(
                'designs',
                designResponse
            );


            writeSuccess(
                200,
                'Architecture designs loaded successfully.',
                data
            );

        } catch (
            Exception ex
        ) {

            System.debug(
                LoggingLevel.ERROR,
                'ArchitectureDesignMobileApi GET ERROR: ' +
                ex.getMessage() +
                ' | LINE: ' +
                ex.getLineNumber()
            );


            writeError(
                500,
                'Unable to load Architecture Designs.'
            );
        }
    }


    // =========================================================
    // POST
    //
    // Approved:
    //
    // {
    //   "leadId": "00Q...",
    //   "opportunityId": "006...",
    //   "designId": "a0...",
    //   "status": "Approved"
    // }
    //
    // Changes Requested:
    //
    // {
    //   "leadId": "00Q...",
    //   "opportunityId": "006...",
    //   "designId": "a0...",
    //   "status": "Changes Requested",
    //   "comments": "Please change..."
    // }
    // =========================================================

    @HttpPost
    global static void doPost() {

        try {

            RestRequest request =
                RestContext.request;


            // =================================================
            // VALIDATE REQUEST BODY
            // =================================================

            if (
                request.requestBody == null ||
                String.isBlank(
                    request.requestBody.toString()
                )
            ) {

                writeError(
                    400,
                    'Request body is required.'
                );

                return;
            }


            DecisionRequest input =
                (DecisionRequest)
                    JSON.deserialize(
                        request.requestBody.toString(),
                        DecisionRequest.class
                    );


            // =================================================
            // VALIDATE LEAD
            // =================================================

            if (
                input == null ||
                input.leadId == null
            ) {

                writeError(
                    400,
                    'Salesforce Lead ID is required.'
                );

                return;
            }


            // =================================================
            // VALIDATE DESIGN
            // =================================================

            if (
                input.designId == null
            ) {

                writeError(
                    400,
                    'Architecture Design ID is required.'
                );

                return;
            }


            // =================================================
            // VALIDATE RESPONSE STATUS
            // =================================================

            if (
                String.isBlank(
                    input.status
                )
            ) {

                writeError(
                    400,
                    'Response status is required.'
                );

                return;
            }


            String responseStatus =
                input.status.trim();


            if (
                responseStatus !=
                    STATUS_APPROVED &&
                responseStatus !=
                    STATUS_CHANGES_REQUESTED
            ) {

                writeError(
                    400,
                    'Status must be Approved or Changes Requested.'
                );

                return;
            }


            // =================================================
            // COMMENTS REQUIRED FOR CHANGES REQUESTED
            // =================================================

            if (
                responseStatus ==
                    STATUS_CHANGES_REQUESTED &&
                String.isBlank(
                    input.comments
                )
            ) {

                writeError(
                    400,
                    'Please describe the changes required.'
                );

                return;
            }


            // =================================================
            // RESOLVE LEAD -> OPPORTUNITY
            // =================================================

            ProspectContext prospect =
                resolveProspectContext(
                    input.leadId
                );


            if (
                prospect == null
            ) {

                writeError(
                    404,
                    'Converted prospect details were not found.'
                );

                return;
            }


            Id opportunityId =
                prospect.opportunityId;


            // =================================================
            // VALIDATE OPPORTUNITY
            // =================================================

            if (
                input.opportunityId != null &&
                input.opportunityId !=
                    opportunityId
            ) {

                writeError(
                    403,
                    'You are not authorized to access this Opportunity.'
                );

                return;
            }


            Id designId =
                input.designId;


            // =================================================
            // GET ARCHITECTURE DESIGN
            // =================================================

            List<Architecture_Design__c>
                matchingDesigns = [
                    SELECT
                        Id,
                        Opportunity__c,
                        Status__c,
                        Comments__c
                    FROM Architecture_Design__c
                    WHERE Id = :designId
                    AND Opportunity__c = :opportunityId
                    LIMIT 1
                ];


            if (
                matchingDesigns.isEmpty()
            ) {

                writeError(
                    404,
                    'Architecture Design was not found.'
                );

                return;
            }


            Architecture_Design__c design =
                matchingDesigns[0];


            // =================================================
            // ALLOW RESPONSE ONLY WHEN SENT
            // =================================================

            if (
                design.Status__c !=
                    STATUS_SENT
            ) {

                writeError(
                    409,
                    'A response has already been submitted for this design.'
                );

                return;
            }


            // =================================================
            // PREPARE UPDATE
            //
            // Existing ArchitectureDesignTrigger will continue
            // to fire from this DML operation.
            // =================================================

            design.Status__c =
                responseStatus;


            if (
                responseStatus ==
                    STATUS_APPROVED
            ) {

                if (
                    String.isBlank(
                        input.comments
                    )
                ) {

                    design.Comments__c =
                        'Approved By Client';

                } else {

                    design.Comments__c =
                        input.comments.trim();
                }

            } else {

                design.Comments__c =
                    input.comments.trim();
            }


          // =================================================
// UPDATE DESIGN
//
// Mobile REST runs through the Site Guest User.
// Execute this controlled DML in SYSTEM MODE.
//
// Existing ArchitectureDesignTrigger will still fire.
// =================================================

Database.SaveResult saveResult =
    Database.update(
        design,
        false,
        AccessLevel.SYSTEM_MODE
    );


            if (
                !saveResult.isSuccess()
            ) {

                String errorMessage =
                    'Unable to update Architecture Design.';


                Database.Error[] saveErrors =
                    saveResult.getErrors();


                if (
                    saveErrors != null &&
                    !saveErrors.isEmpty()
                ) {

                    Database.Error saveError =
                        saveErrors[0];


                    errorMessage =
                        String.valueOf(
                            saveError.getStatusCode()
                        ) +
                        ': ' +
                        saveError.getMessage();
                }


                System.debug(
                    LoggingLevel.ERROR,
                    'ARCHITECTURE DESIGN UPDATE ERROR: ' +
                    errorMessage
                );


                writeError(
                    500,
                    errorMessage
                );


                return;
            }


            // =================================================
            // SUCCESS RESPONSE
            // =================================================

            Map<String, Object> data =
                new Map<String, Object>();


            data.put(
                'designId',
                design.Id
            );


            data.put(
                'opportunityId',
                opportunityId
            );


            data.put(
                'status',
                design.Status__c
            );


            data.put(
                'comments',
                design.Comments__c
            );


            String successMessage =
                responseStatus ==
                    STATUS_APPROVED
                    ? 'Architecture Design approved successfully.'
                    : 'Requested changes submitted successfully.';


            writeSuccess(
                200,
                successMessage,
                data
            );

        } catch (
            Exception ex
        ) {

            // =================================================
            // RETURN REAL ERROR DURING TESTING
            // =================================================

            String errorMessage =
                ex.getTypeName() +
                ': ' +
                ex.getMessage() +
                ' | Line: ' +
                ex.getLineNumber();


            System.debug(
                LoggingLevel.ERROR,
                'ArchitectureDesignMobileApi POST ERROR: ' +
                errorMessage
            );


            writeError(
                500,
                errorMessage
            );
        }
    }


    // =========================================================
    // FILE DOWNLOAD / PREVIEW
    // =========================================================

    private static void serveFile() {

        RestRequest request =
            RestContext.request;


        Id leadId =
            parseId(
                request.params.get(
                    'leadId'
                )
            );


        Id requestedOpportunityId =
            parseId(
                request.params.get(
                    'opportunityId'
                )
            );


        Id designId =
            parseId(
                request.params.get(
                    'designId'
                )
            );


        Id versionId =
            parseId(
                request.params.get(
                    'versionId'
                )
            );


        // =====================================================
        // VALIDATE PARAMETERS
        // =====================================================

        if (
            leadId == null
        ) {

            writeError(
                400,
                'Salesforce Lead ID is required.'
            );

            return;
        }


        if (
            designId == null
        ) {

            writeError(
                400,
                'Architecture Design ID is required.'
            );

            return;
        }


        if (
            versionId == null
        ) {

            writeError(
                400,
                'File Version ID is required.'
            );

            return;
        }


        // =====================================================
        // RESOLVE PROSPECT
        // =====================================================

        ProspectContext prospect =
            resolveProspectContext(
                leadId
            );


        if (
            prospect == null
        ) {

            writeError(
                404,
                'Converted prospect details were not found.'
            );

            return;
        }


        Id opportunityId =
            prospect.opportunityId;


        // =====================================================
        // VALIDATE OPPORTUNITY
        // =====================================================

        if (
            requestedOpportunityId != null &&
            requestedOpportunityId !=
                opportunityId
        ) {

            writeError(
                403,
                'You are not authorized to access this Opportunity.'
            );

            return;
        }


        // =====================================================
        // VALIDATE DESIGN
        // =====================================================

        List<Architecture_Design__c> designs = [
            SELECT
                Id,
                Opportunity__c
            FROM Architecture_Design__c
            WHERE Id = :designId
            AND Opportunity__c = :opportunityId
            LIMIT 1
        ];


        if (
            designs.isEmpty()
        ) {

            writeError(
                404,
                'Architecture Design was not found.'
            );

            return;
        }


        // =====================================================
        // VERIFY VERSION BELONGS TO DESIGN
        // =====================================================

        Boolean versionIsAuthorized =
            false;


        List<ContentDocumentLink> links = [
            SELECT
                ContentDocumentId,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :designId
        ];


        for (
            ContentDocumentLink link :
            links
        ) {

            Id latestVersionId =
                link.ContentDocument.LatestPublishedVersionId;


            if (
                latestVersionId ==
                    versionId
            ) {

                versionIsAuthorized =
                    true;

                break;
            }
        }


        if (
            !versionIsAuthorized
        ) {

            writeError(
                403,
                'This file is not associated with the Architecture Design.'
            );

            return;
        }


        // =====================================================
        // GET FILE
        // =====================================================

        List<ContentVersion> versions = [
            SELECT
                Id,
                Title,
                FileExtension,
                VersionData
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];


        if (
            versions.isEmpty()
        ) {

            writeError(
                404,
                'Architecture Design file was not found.'
            );

            return;
        }


        ContentVersion version =
            versions[0];


        String fileName =
            version.Title;


        if (
            !String.isBlank(
                version.FileExtension
            )
        ) {

            fileName =
                fileName +
                '.' +
                version.FileExtension;
        }


        fileName =
            fileName.replace(
                '"',
                ''
            );


        // =====================================================
        // RAW FILE RESPONSE
        // =====================================================

        RestResponse response =
            RestContext.response;


        response.statusCode =
            200;


        response.addHeader(
            'Content-Type',
            getContentType(
                version.FileExtension
            )
        );


        response.addHeader(
            'Content-Disposition',
            'inline; filename="' +
            fileName +
            '"'
        );


        response.responseBody =
            version.VersionData;
    }


    // =========================================================
    // LEAD -> CONVERTED OPPORTUNITY
    // =========================================================

    private static ProspectContext
        resolveProspectContext(
            Id leadId
        ) {

        if (
            leadId == null
        ) {

            return null;
        }


        List<Lead> leads = [
            SELECT
                Id,
                IsConverted,
                ConvertedOpportunityId
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];


        if (
            leads.isEmpty()
        ) {

            return null;
        }


        Lead prospect =
            leads[0];


        if (
            prospect.IsConverted != true ||
            prospect.ConvertedOpportunityId ==
                null
        ) {

            return null;
        }


        ProspectContext context =
            new ProspectContext();


        context.leadId =
            prospect.Id;


        context.opportunityId =
            prospect.ConvertedOpportunityId;


        return context;
    }


    // =========================================================
    // MIME TYPE
    // =========================================================

    private static String getContentType(
        String extension
    ) {

        if (
            String.isBlank(
                extension
            )
        ) {

            return 'application/octet-stream';
        }


        String ext =
            extension.trim().toLowerCase();


        if (
            ext == 'png'
        ) {

            return 'image/png';
        }


        if (
            ext == 'jpg' ||
            ext == 'jpeg'
        ) {

            return 'image/jpeg';
        }


        if (
            ext == 'gif'
        ) {

            return 'image/gif';
        }


        if (
            ext == 'webp'
        ) {

            return 'image/webp';
        }


        if (
            ext == 'pdf'
        ) {

            return 'application/pdf';
        }


        if (
            ext == 'zip'
        ) {

            return 'application/zip';
        }


        if (
            ext == 'glb'
        ) {

            return 'model/gltf-binary';
        }


        if (
            ext == 'gltf'
        ) {

            return 'model/gltf+json';
        }


        return 'application/octet-stream';
    }


    // =========================================================
    // SAFE SALESFORCE ID PARSER
    // =========================================================

    private static Id parseId(
        String value
    ) {

        if (
            String.isBlank(
                value
            )
        ) {

            return null;
        }


        try {

            return Id.valueOf(
                value.trim()
            );

        } catch (
            Exception ex
        ) {

            return null;
        }
    }


    // =========================================================
    // SUCCESS RESPONSE
    // =========================================================

    private static void writeSuccess(
        Integer statusCode,
        String message,
        Object data
    ) {

        RestResponse response =
            RestContext.response;


        response.statusCode =
            statusCode;


        response.addHeader(
            'Content-Type',
            'application/json'
        );


        Map<String, Object> body =
            new Map<String, Object>();


        body.put(
            'success',
            true
        );


        body.put(
            'message',
            message
        );


        body.put(
            'data',
            data
        );


        response.responseBody =
            Blob.valueOf(
                JSON.serialize(
                    body
                )
            );
    }


    // =========================================================
    // ERROR RESPONSE
    // =========================================================

    private static void writeError(
        Integer statusCode,
        String message
    ) {

        RestResponse response =
            RestContext.response;


        response.statusCode =
            statusCode;


        response.addHeader(
            'Content-Type',
            'application/json'
        );


        Map<String, Object> body =
            new Map<String, Object>();


        body.put(
            'success',
            false
        );


        body.put(
            'message',
            message
        );


        response.responseBody =
            Blob.valueOf(
                JSON.serialize(
                    body
                )
            );
    }
}