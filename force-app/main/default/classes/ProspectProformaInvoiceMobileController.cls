@RestResource(urlMapping='/registration/lead/proforma-invoice/*')
global without sharing class ProspectProformaInvoiceMobileController {

    /*
     * =========================================================
     * STATUS VALUES
     * =========================================================
     */
    private static final String STATUS_APPROVED =
        'Approved';

    private static final String STATUS_CHANGES_REQUESTED =
        'Changes Requested';


    /*
     * =========================================================
     * GET PROFORMA INVOICE
     * =========================================================
     */
    @HttpGet
    global static void getProformaInvoice() {

        try {

            RestRequest request =
                RestContext.request;

            String leadId =
                request.params.get('leadId');

            String invoiceId =
                request.params.get('invoiceId');

            String secureToken =
                request.params.get('secureToken');

            String download =
                request.params.get('download');

            String fileVersionId =
                request.params.get('fileVersionId');


            if (String.isBlank(leadId)) {

                writeError(
                    400,
                    'leadId is required.'
                );

                return;
            }


            if (request.params.get('list') == 'true') {
                listInvoicesForLead(leadId);
                return;
            }
            AuthorizedInvoice auth;


            /*
             * =====================================================
             * PROFILE FLOW
             * =====================================================
             */
            if (
                String.isBlank(invoiceId) &&
                String.isBlank(secureToken)
            ) {

                auth =
                    findLatestInvoiceForLead(
                        leadId
                    );
            }

            /*
             * =====================================================
             * EXACT PROFORMA FLOW
             * =====================================================
             */
            else {

                if (
                    String.isBlank(invoiceId) ||
                    String.isBlank(secureToken)
                ) {

                    writeError(
                        400,
                        'invoiceId and secureToken must both be provided.'
                    );

                    return;
                }


                auth =
                    authorizeInvoice(
                        leadId,
                        invoiceId,
                        secureToken
                    );
            }


            if (auth == null) {
                return;
            }


            /*
             * =====================================================
             * FILE DOWNLOAD
             * =====================================================
             */
            if (
                download == 'true' &&
                !String.isBlank(fileVersionId)
            ) {

                downloadInvoiceFile(
                    auth.invoice,
                    fileVersionId
                );

                return;
            }


            /*
             * =====================================================
             * GET RELATED FILES
             * =====================================================
             */
            List<Object> files =
                getInvoiceFiles(
                    auth.invoice,
                    leadId,
                    auth.invoice.Secure_Token__c
                );


            /*
             * =====================================================
             * BUILD RESPONSE
             * =====================================================
             */
            Map<String, Object> invoiceData =
                new Map<String, Object>();


            invoiceData.put(
                'id',
                auth.invoice.Id
            );

            invoiceData.put(
                'invoiceId',
                auth.invoice.Id
            );

            invoiceData.put(
                'name',
                auth.invoice.Name
            );

            invoiceData.put(
                'status',
                auth.invoice.Status__c
            );

            invoiceData.put(
                'opportunityId',
                auth.invoice.Opportunity__c
            );

            invoiceData.put(
                'opportunityName',
                auth.invoice.Opportunity__r != null
                    ? auth.invoice.Opportunity__r.Name
                    : null
            );

            invoiceData.put(
                'projectId',
                auth.invoice.Project__c
            );

            invoiceData.put(
                'projectName',
                auth.invoice.Project__r != null
                    ? auth.invoice.Project__r.Name
                    : null
            );

            invoiceData.put(
                'clientComments',
                auth.invoice.Client_Comments__c
            );

            invoiceData.put(
                'managerApproval',
                auth.invoice.Manager_Approval__c
            );

            invoiceData.put(
                'managerComments',
                auth.invoice.Manager_Comments__c
            );

            invoiceData.put(
                'createdDate',
                auth.invoice.CreatedDate
            );

            invoiceData.put(
                'secureToken',
                auth.invoice.Secure_Token__c
            );


            Map<String, Object> result =
                new Map<String, Object>();


            result.put(
                'success',
                true
            );

            result.put(
                'invoiceAvailable',
                true
            );

            result.put(
                'invoice',
                invoiceData
            );

            result.put(
                'files',
                files
            );


            writeJson(
                200,
                result
            );

        } catch (Exception e) {

            writeError(
                500,
                'Unable to get Proforma Invoice: ' +
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
    global static void submitProformaResponse() {

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


            String requestBody =
                request.requestBody.toString();


            if (String.isBlank(requestBody)) {

                writeError(
                    400,
                    'Request body is required.'
                );

                return;
            }


            Map<String, Object> input =
                (Map<String, Object>)
                JSON.deserializeUntyped(
                    requestBody
                );


            String leadId =
                getString(
                    input,
                    'leadId'
                );

            String invoiceId =
                getString(
                    input,
                    'invoiceId'
                );

            String secureToken =
                getString(
                    input,
                    'secureToken'
                );

            String action =
                getString(
                    input,
                    'action'
                );

            String comments =
                getString(
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


            if (String.isBlank(invoiceId)) {

                writeError(
                    400,
                    'invoiceId is required.'
                );

                return;
            }


            if (String.isBlank(secureToken)) {

                writeError(
                    400,
                    'secureToken is required.'
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


            AuthorizedInvoice auth =
                authorizeInvoice(
                    leadId,
                    invoiceId,
                    secureToken
                );


            if (auth == null) {
                return;
            }


            // Lock and recheck the persisted record before accepting a decision.
            Id authorizedInvoiceId = auth.invoice.Id;
            Proforma_Invoice__c invoice = [
                SELECT Id, Status__c, Client_Comments__c, Secure_Token__c, Opportunity__c
                FROM Proforma_Invoice__c WHERE Id = :authorizedInvoiceId
                LIMIT 1 FOR UPDATE
            ];
            if (invoice.Opportunity__c != auth.lead.ConvertedOpportunityId ||
                String.isBlank(invoice.Secure_Token__c) ||
                !invoice.Secure_Token__c.trim().equals(secureToken.trim())) {
                writeError(403, 'You are not authorized to access this Proforma Invoice.');
                return;
            }


            /*
             * =====================================================
             * PREVENT DUPLICATE RESPONSE
             * =====================================================
             */
            if (
                invoice.Status__c != 'Sent'
            ) {

                writeError(
                    409,
                    'A response has already been submitted for this Proforma Invoice.'
                );

                return;
            }


            action =
                action.trim().toUpperCase();


            /*
             * =====================================================
             * APPROVE
             * =====================================================
             */
            if (action == 'APPROVE') {

                invoice.Status__c =
                    STATUS_APPROVED;


                invoice.Client_Comments__c = String.isBlank(comments)
                    ? 'Approved By Client'
                    : comments.trim();
            }


            /*
             * =====================================================
             * REQUEST CHANGES
             * =====================================================
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


                invoice.Status__c =
                    STATUS_CHANGES_REQUESTED;


                invoice.Client_Comments__c =
                    comments.trim();
            }


            else {

                writeError(
                    400,
                    'Only APPROVE or REQUEST_CHANGES are allowed.'
                );

                return;
            }


            /*
             * =====================================================
             * LOCKED SYSTEM MODE UPDATE
             * =====================================================
             */
            // Save synchronously: a success response means the decision is committed.
            Database.update(invoice, AccessLevel.SYSTEM_MODE);


            Map<String, Object> result =
                new Map<String, Object>();


            result.put(
                'success',
                true
            );


            if (action == 'APPROVE') {

                result.put(
                    'message',
                    'Proforma Invoice approved successfully.'
                );

            } else {

                result.put(
                    'message',
                    'Change request submitted successfully.'
                );
            }


            result.put(
                'invoiceId',
                invoice.Id
            );

            result.put(
                'status',
                invoice.Status__c
            );

            result.put(
                'clientComments',
                invoice.Client_Comments__c
            );


            writeJson(
                200,
                result
            );

        } catch (Exception e) {

            writeError(
                500,
                'Unable to submit response: ' +
                e.getMessage()
            );
        }
    }


    /*
     * =========================================================
     * FIND LATEST PROFORMA FOR LEAD
     * =========================================================
     */
/*
 * =========================================================
 * FIND LATEST PROFORMA FOR LEAD
 * =========================================================
 *
 * IMPORTANT:
 * This method must return the latest Proforma regardless of
 * whether the status is:
 *
 * Sent
 * Approved
 * Changes Requested
 *
 * Status must NOT control whether the client can VIEW it.
 * POST logic controls whether another response is allowed.
 */
private static AuthorizedInvoice findLatestInvoiceForLead(
    String leadId
) {

    if (String.isBlank(leadId)) {

        writeError(
            400,
            'leadId is required.'
        );

        return null;
    }


    /*
     * =====================================================
     * GET CONVERTED LEAD IN SYSTEM MODE
     * =====================================================
     */
    List<Lead> leadList =
        Database.query(
            'SELECT ' +
                'Id, ' +
                'FirstName, ' +
                'LastName, ' +
                'Email, ' +
                'IsConverted, ' +
                'ConvertedOpportunityId ' +
            'FROM Lead ' +
            'WHERE Id = :leadId ' +
            'LIMIT 1',
            AccessLevel.SYSTEM_MODE
        );


    if (leadList.isEmpty()) {

        writeError(
            404,
            'Prospect Lead not found.'
        );

        return null;
    }


    Lead prospectLead =
        leadList[0];


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


    Id convertedOpportunityId =
        prospectLead.ConvertedOpportunityId;


    /*
     * =====================================================
     * GET LATEST PROFORMA
     * =====================================================
     *
     * IMPORTANT:
     *
     * Include only invoices sent for client review and their recorded responses.
     * NO Secure_Token__c != null filter.
     * NO Manager_Approval__c filter.
     *
     * We only identify the Proforma by its Opportunity.
     */
    List<Proforma_Invoice__c> invoiceList =
        Database.query(
            'SELECT ' +
                'Id, ' +
                'Name, ' +

                'Opportunity__c, ' +
                'Opportunity__r.Name, ' +

                'Project__c, ' +
                'Project__r.Name, ' +

                'Status__c, ' +

                'Client_Comments__c, ' +

                'Manager_Approval__c, ' +
                'Manager_Comments__c, ' +

                'Related_File_Id__c, ' +
                'Secure_Token__c, ' +

                'CreatedDate ' +

            'FROM Proforma_Invoice__c ' +

            'WHERE Opportunity__c = :convertedOpportunityId ' +
            'AND Status__c IN (\'Sent\', \'Approved\', \'Changes Requested\') ' +

            'ORDER BY CreatedDate DESC ' +

            'LIMIT 1',
            AccessLevel.SYSTEM_MODE
        );


    if (invoiceList.isEmpty()) {

        writeError(
            404,
            'No Proforma Invoice is available yet.'
        );

        return null;
    }


    Proforma_Invoice__c invoice =
        invoiceList[0];


    /*
     * =====================================================
     * BUILD RESULT
     * =====================================================
     */
    AuthorizedInvoice result =
        new AuthorizedInvoice();


    result.lead =
        prospectLead;


    result.invoice =
        invoice;


    return result;
}


    /*
     * =========================================================
     * AUTHORIZE EXACT PROFORMA
     * =========================================================
     */
/*
 * =========================================================
 * AUTHORIZE EXACT PROFORMA
 * =========================================================
 *
 * Used when Flutter opens the actual Proforma screen.
 *
 * Supports:
 * - Sent
 * - Approved
 * - Changes Requested
 *
 * Status does NOT affect viewing.
 */
private static AuthorizedInvoice authorizeInvoice(
    String leadId,
    String invoiceId,
    String secureToken
) {

    /*
     * =====================================================
     * REQUIRED VALUES
     * =====================================================
     */
    if (
        String.isBlank(leadId) ||
        String.isBlank(invoiceId) ||
        String.isBlank(secureToken)
    ) {

        writeError(
            400,
            'leadId, invoiceId and secureToken are required.'
        );

        return null;
    }


    /*
     * =====================================================
     * GET LEAD IN SYSTEM MODE
     * =====================================================
     */
    List<Lead> leadList =
        Database.query(
            'SELECT ' +
                'Id, ' +
                'FirstName, ' +
                'LastName, ' +
                'Email, ' +
                'IsConverted, ' +
                'ConvertedOpportunityId ' +
            'FROM Lead ' +
            'WHERE Id = :leadId ' +
            'LIMIT 1',
            AccessLevel.SYSTEM_MODE
        );


    if (leadList.isEmpty()) {

        writeError(
            404,
            'Prospect Lead not found.'
        );

        return null;
    }


    Lead prospectLead =
        leadList[0];


    /*
     * =====================================================
     * CHECK LEAD CONVERSION
     * =====================================================
     */
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


    /*
     * =====================================================
     * VALIDATE INVOICE ID
     * =====================================================
     */
    Id normalizedInvoiceId;

    try {

        normalizedInvoiceId =
            (Id) invoiceId.trim();

    } catch (Exception e) {

        writeError(
            400,
            'Invalid Proforma Invoice ID.'
        );

        return null;
    }


    /*
     * =====================================================
     * GET EXACT PROFORMA IN SYSTEM MODE
     * =====================================================
     *
     * IMPORTANT:
     *
     * Query only by invoice ID here.
     *
     * Do NOT filter by:
     * - Status__c
     * - Secure_Token__c
     * - Manager_Approval__c
     *
     * Those validations happen separately below.
     */
    List<Proforma_Invoice__c> invoiceList =
        Database.query(
            'SELECT ' +
                'Id, ' +
                'Name, ' +

                'Opportunity__c, ' +
                'Opportunity__r.Name, ' +

                'Project__c, ' +
                'Project__r.Name, ' +

                'Status__c, ' +

                'Client_Comments__c, ' +

                'Manager_Approval__c, ' +
                'Manager_Comments__c, ' +

                'Related_File_Id__c, ' +
                'Secure_Token__c, ' +

                'CreatedDate ' +

            'FROM Proforma_Invoice__c ' +

            'WHERE Id = :normalizedInvoiceId ' +

            'LIMIT 1',
            AccessLevel.SYSTEM_MODE
        );


    /*
     * =====================================================
     * INVOICE MUST EXIST
     * =====================================================
     */
    if (invoiceList.isEmpty()) {

        writeError(
            404,
            'Proforma Invoice not found.'
        );

        return null;
    }


    Proforma_Invoice__c invoice =
        invoiceList[0];


    /*
     * =====================================================
     * VALIDATE SECURE TOKEN
     * =====================================================
     *
     * We still require exactly the same secure token.
     *
     * Approved / Changes Requested records remain viewable.
     */
    if (
        String.isBlank(invoice.Secure_Token__c) ||
        !invoice.Secure_Token__c.trim().equals(secureToken.trim())
    ) {

        writeError(
            403,
            'Invalid or expired Proforma access token.'
        );

        return null;
    }


    /*
     * =====================================================
     * VALIDATE OPPORTUNITY
     * =====================================================
     */
    if (
        invoice.Opportunity__c == null ||
        invoice.Opportunity__c !=
            prospectLead.ConvertedOpportunityId
    ) {

        writeError(
            403,
            'You are not authorized to access this Proforma Invoice.'
        );

        return null;
    }


    if (invoice.Status__c != 'Sent' && invoice.Status__c != 'Approved' && invoice.Status__c != 'Changes Requested') {
        writeError(404, 'Proforma Invoice is not available for client review.');
        return null;
    }

    /*
     * =====================================================
     * SUCCESS
     * =====================================================
     */
    AuthorizedInvoice result =
        new AuthorizedInvoice();


    result.lead =
        prospectLead;


    result.invoice =
        invoice;


    return result;
}


    /*
     * =========================================================
     * GET FILES
     * =========================================================
     */
 /*
 * =========================================================
 * GET PROFORMA FILES
 * =========================================================
 *
 * Reads Proforma files in SYSTEM MODE so the Experience
 * Cloud Guest User can still view the PDF after the
 * Proforma becomes Approved / Changes Requested.
 */
private static List<Object> getInvoiceFiles(
        Proforma_Invoice__c invoice,
        String leadId,
        String secureToken
    ) {

        List<Object> files =
            new List<Object>();

        Set<Id> addedContentDocuments =
            new Set<Id>();


        /*
         * =====================================================
         * CONTENT DOCUMENT LINKS
         * =====================================================
         */
        Id invoiceId =
            invoice.Id;


        List<ContentDocumentLink> links =
            Database.query(
                'SELECT ' +
                    'Id, ' +
                    'ContentDocumentId, ' +
                    'ContentDocument.Title, ' +
                    'ContentDocument.FileType, ' +
                    'ContentDocument.LatestPublishedVersionId ' +
                'FROM ContentDocumentLink ' +
                'WHERE LinkedEntityId = :invoiceId',
                AccessLevel.SYSTEM_MODE
            );


        /*
         * =====================================================
         * ADD LINKED FILES
         * =====================================================
         */
        for (ContentDocumentLink link : links) {

            if (
                link.ContentDocumentId == null ||
                link.ContentDocument == null ||
                link.ContentDocument.LatestPublishedVersionId == null
            ) {
                continue;
            }


            addedContentDocuments.add(
                link.ContentDocumentId
            );


            files.add(
                buildFileResponse(
                    link.ContentDocument.Title,
                    link.ContentDocument.FileType,
                    link.ContentDocument.LatestPublishedVersionId,
                    invoice.Id,
                    leadId,
                    secureToken
                )
            );
        }


        /*
         * =====================================================
         * RELATED FILE ID FALLBACK
         * =====================================================
         */
        if (
            String.isBlank(
                invoice.Related_File_Id__c
            )
        ) {

            return files;
        }


        String relatedFileId =
            invoice.Related_File_Id__c.trim();


        /*
         * =====================================================
         * CONTENT DOCUMENT
         * =====================================================
         *
         * 069 = ContentDocument
         */
        if (
            relatedFileId.startsWith('069')
        ) {

            Id contentDocumentId;


            try {

                contentDocumentId =
                    (Id) relatedFileId;

            } catch (Exception e) {

                return files;
            }


            List<ContentDocument> documents =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'Title, ' +
                        'FileType, ' +
                        'LatestPublishedVersionId ' +
                    'FROM ContentDocument ' +
                    'WHERE Id = :contentDocumentId ' +
                    'LIMIT 1',
                    AccessLevel.SYSTEM_MODE
                );


            if (
                !documents.isEmpty()
            ) {

                ContentDocument document =
                    documents[0];


                /*
                 * Avoid duplicate file when it was already
                 * returned through ContentDocumentLink.
                 */
                if (
                    document.LatestPublishedVersionId != null &&
                    !addedContentDocuments.contains(
                        document.Id
                    )
                ) {

                    files.add(
                        buildFileResponse(
                            document.Title,
                            document.FileType,
                            document.LatestPublishedVersionId,
                            invoice.Id,
                            leadId,
                            secureToken
                        )
                    );
                }
            }
        }


        /*
         * =====================================================
         * CONTENT VERSION
         * =====================================================
         *
         * 068 = ContentVersion
         */
        else if (
            relatedFileId.startsWith('068')
        ) {

            Id contentVersionId;


            try {

                contentVersionId =
                    (Id) relatedFileId;

            } catch (Exception e) {

                return files;
            }


            List<ContentVersion> versions =
                Database.query(
                    'SELECT ' +
                        'Id, ' +
                        'Title, ' +
                        'FileExtension, ' +
                        'ContentDocumentId ' +
                    'FROM ContentVersion ' +
                    'WHERE Id = :contentVersionId ' +
                    'LIMIT 1',
                    AccessLevel.SYSTEM_MODE
                );


            if (
                !versions.isEmpty()
            ) {

                ContentVersion version =
                    versions[0];


                if (
                    !addedContentDocuments.contains(
                        version.ContentDocumentId
                    )
                ) {

                    files.add(
                        buildFileResponse(
                            version.Title,
                            version.FileExtension,
                            version.Id,
                            invoice.Id,
                            leadId,
                            secureToken
                        )
                    );
                }
            }
        }


        return files;
    }

    /*
     * =========================================================
     * BUILD FILE RESPONSE
     * =========================================================
     */
    private static Map<String, Object> buildFileResponse(
        String title,
        String fileType,
        Id fileVersionId,
        Id invoiceId,
        String leadId,
        String secureToken
    ) {

        String downloadPath =
            '/services/apexrest/' +
            'registration/lead/proforma-invoice' +

            '?leadId=' +
            EncodingUtil.urlEncode(
                leadId,
                'UTF-8'
            ) +

            '&invoiceId=' +
            EncodingUtil.urlEncode(
                String.valueOf(invoiceId),
                'UTF-8'
            ) +

            '&secureToken=' +
            EncodingUtil.urlEncode(
                secureToken,
                'UTF-8'
            ) +

            '&download=true' +

            '&fileVersionId=' +
            EncodingUtil.urlEncode(
                String.valueOf(fileVersionId),
                'UTF-8'
            );


        Map<String, Object> file =
            new Map<String, Object>();


        file.put(
            'title',
            title
        );

        file.put(
            'fileType',
            fileType
        );

        file.put(
            'fileVersionId',
            fileVersionId
        );

        file.put(
            'downloadPath',
            downloadPath
        );


        return file;
    }


    /*
     * =========================================================
     * DOWNLOAD FILE
     * =========================================================
     */
    private static void downloadInvoiceFile(
        Proforma_Invoice__c invoice,
        String fileVersionId
    ) {

        /*
         * =====================================================
         * VALIDATE FILE VERSION ID
         * =====================================================
         */
        if (
            String.isBlank(fileVersionId)
        ) {

            writeError(
                400,
                'fileVersionId is required.'
            );

            return;
        }


        Id normalizedFileVersionId;


        try {

            normalizedFileVersionId =
                (Id) fileVersionId.trim();

        } catch (Exception e) {

            writeError(
                400,
                'Invalid fileVersionId.'
            );

            return;
        }


        /*
         * =====================================================
         * GET CONTENT VERSION IN SYSTEM MODE
         * =====================================================
         */
        List<ContentVersion> versions =
            Database.query(
                'SELECT ' +
                    'Id, ' +
                    'Title, ' +
                    'FileExtension, ' +
                    'ContentDocumentId, ' +
                    'VersionData ' +
                'FROM ContentVersion ' +
                'WHERE Id = :normalizedFileVersionId ' +
                'LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );


        if (
            versions.isEmpty()
        ) {

            writeError(
                404,
                'File not found.'
            );

            return;
        }


        ContentVersion version =
            versions[0];


        Boolean allowed =
            false;


        /*
         * =====================================================
         * VERIFY USING RELATED_FILE_ID__C
         * =====================================================
         */
        if (
            !String.isBlank(
                invoice.Related_File_Id__c
            )
        ) {

            String relatedId =
                invoice.Related_File_Id__c.trim();


            if (
                relatedId ==
                    String.valueOf(
                        version.Id
                    ) ||
                relatedId ==
                    String.valueOf(
                        version.ContentDocumentId
                    )
            ) {

                allowed =
                    true;
            }
        }


        /*
         * =====================================================
         * VERIFY USING CONTENT DOCUMENT LINK
         * =====================================================
         */
        if (
            !allowed &&
            version.ContentDocumentId != null
        ) {

            Id invoiceId =
                invoice.Id;

            Id contentDocumentId =
                version.ContentDocumentId;


            List<ContentDocumentLink> links =
                Database.query(
                    'SELECT Id ' +
                    'FROM ContentDocumentLink ' +
                    'WHERE LinkedEntityId = :invoiceId ' +
                    'AND ContentDocumentId = :contentDocumentId ' +
                    'LIMIT 1',
                    AccessLevel.SYSTEM_MODE
                );


            if (
                !links.isEmpty()
            ) {

                allowed =
                    true;
            }
        }


        /*
         * =====================================================
         * BLOCK UNRELATED FILE
         * =====================================================
         */
        if (
            !allowed
        ) {

            writeError(
                403,
                'This file does not belong to the Proforma Invoice.'
            );

            return;
        }


        /*
         * =====================================================
         * RETURN FILE
         * =====================================================
         */
        RestResponse response =
            RestContext.response;
        response.addHeader('Cache-Control', 'no-store');
        response.addHeader('X-Content-Type-Options', 'nosniff');


        response.statusCode =
            200;


        response.addHeader(
            'Content-Type',
            getMimeType(
                version.FileExtension
            )
        );


        String fileName =
            version.Title;


        if (
            !String.isBlank(
                version.FileExtension
            )
        ) {

            fileName +=
                '.' +
                version.FileExtension;
        }


        fileName =
            fileName.replace(
                '"',
                ''
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


    /*
     * =========================================================
     * MIME TYPE
     * =========================================================
     */
    private static String getMimeType(
        String extension
    ) {

        if (String.isBlank(extension)) {

            return
                'application/octet-stream';
        }


        String ext =
            extension.trim().toLowerCase();


        if (ext == 'pdf') {
            return 'application/pdf';
        }


        if (
            ext == 'jpg' ||
            ext == 'jpeg'
        ) {
            return 'image/jpeg';
        }


        if (ext == 'png') {
            return 'image/png';
        }


        if (ext == 'webp') {
            return 'image/webp';
        }


        if (ext == 'doc') {
            return 'application/msword';
        }


        if (ext == 'docx') {
            return
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        }


        if (ext == 'xls') {
            return 'application/vnd.ms-excel';
        }


        if (ext == 'xlsx') {
            return
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        }


        return
            'application/octet-stream';
    }


    /*
     * =========================================================
     * STRING HELPER
     * =========================================================
     */
    private static String getString(
        Map<String, Object> input,
        String fieldName
    ) {

        if (
            input == null ||
            !input.containsKey(fieldName) ||
            input.get(fieldName) == null
        ) {

            return null;
        }


        return String.valueOf(
            input.get(fieldName)
        ).trim();
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

        Map<String, Object> error =
            new Map<String, Object>();


        error.put(
            'success',
            false
        );

        error.put(
            'invoiceAvailable',
            false
        );

        error.put(
            'message',
            message
        );


        writeJson(
            statusCode,
            error
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
        response.addHeader('Cache-Control', 'no-store');
        response.addHeader('X-Content-Type-Options', 'nosniff');


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


    /*
     * =========================================================
     * WRAPPER
     * =========================================================
     */
    // List metadata without per-invoice file queries. Exact GET loads attachments on demand.
    private static void listInvoicesForLead(String leadId) {
        Id normalizedLeadId;
        try {
            normalizedLeadId = (Id) leadId;
            if (normalizedLeadId.getSObjectType() != Lead.SObjectType) {
                writeError(400, 'Invalid Lead ID.');
                return;
            }
        } catch (Exception ignored) {
            writeError(400, 'Invalid Lead ID.');
            return;
        }
        List<Lead> leads = [
            SELECT Id, IsConverted, ConvertedOpportunityId
            FROM Lead WHERE Id = :normalizedLeadId WITH SYSTEM_MODE LIMIT 1
        ];
        if (leads.isEmpty()) { writeError(404, 'Prospect Lead not found.'); return; }
        List<Object> items = new List<Object>();
        if (leads[0].IsConverted && leads[0].ConvertedOpportunityId != null) {
            Id opportunityId = leads[0].ConvertedOpportunityId;
            for (Proforma_Invoice__c invoice : [
                SELECT Id, Name, Opportunity__c, Opportunity__r.Name, Status__c,
                    Client_Comments__c, Secure_Token__c, Manager_Approval__c, CreatedDate
                FROM Proforma_Invoice__c
                WHERE Opportunity__c = :opportunityId
                AND Status__c IN ('Sent', 'Approved', 'Changes Requested')
                WITH SYSTEM_MODE ORDER BY CreatedDate DESC
            ]) {
                items.add(new Map<String, Object>{
                    'invoiceId' => invoice.Id, 'name' => invoice.Name,
                    'opportunityId' => invoice.Opportunity__c,
                    'opportunityName' => invoice.Opportunity__r.Name,
                    'status' => invoice.Status__c, 'managerApproval' => invoice.Manager_Approval__c,
                    'clientComments' => invoice.Client_Comments__c,
                    'secureToken' => invoice.Secure_Token__c,
                    'createdDate' => invoice.CreatedDate
                });
            }
        }
        writeJson(200, new Map<String, Object>{'success' => true, 'invoices' => items});
    }
    private class AuthorizedInvoice {

        public Lead lead;

        public Proforma_Invoice__c invoice;
    }
}